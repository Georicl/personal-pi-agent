import AppKit
import Foundation
import ImageIO
import Testing
@testable import PersonalPi

@Suite("Artifact review")
struct WorkbenchTests {
    private func artifact(_ root: URL, content: String, version: Int = 1) -> TextArtifact {
        TextArtifact(schemaVersion: 1, kind: "text", id: "report-v\(version)", artifactId: "report",
            version: version, parentVersion: version > 1 ? version-1 : nil, title: "Results", cwd: root.path,
            sessionId: nil, createdAt: "2026-09-09T00:00:00Z", sourcePath: root.appendingPathComponent("document.md").path,
            contentHash: ArtifactReviewAttachment.hash(Data(content.utf8)), sources: ["source-1"])
    }

    @Test("Unicode selections retain exact UTF-16 anchors and reject changed files or scopes")
    func selectedText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "# 研究 🧬\n第一段。\n第二段。"
        let item = artifact(root, content: content)
        try content.write(toFile: item.sourcePath, atomically: true, encoding: .utf8)
        let range = (content as NSString).range(of: "第二段。")
        let review = try ArtifactReviewAttachment.text(item, content: content, range: range, comment: "补充样本量")
        #expect(review.reference.selectedText == "第二段。")
        #expect(review.reference.utf16Location == range.location)
        try ArtifactReviewAttachment.validate([review], cwd: root.path)
        #expect(throws: (any Error).self) { try ArtifactReviewAttachment.validate([review], cwd: root.appendingPathComponent("other").path) }
        try "changed".write(toFile: item.sourcePath, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try ArtifactReviewAttachment.validate([review], cwd: root.path) }
        let message = try ArtifactReviewAttachment.message("Revise", attachments: [review])
        #expect(message.contains("workbench_read_text"))
        #expect(message.contains(item.contentHash))
        #expect(message.contains("补充样本量"))
        let displayed = ArtifactReviewAttachment.displayMessage(message)
        #expect(displayed.contains("第二段。"))
        #expect(!displayed.contains("baseHash"))
        #expect(try !ArtifactReviewAttachment.message("/compact", attachments: [review]).hasPrefix("/"))
    }

    @Test("Reverse drags use normalized image coordinates and invalid selections are rejected")
    func imageSelection() throws {
        let region = try #require(ReviewRegion.selection(start: CGPoint(x: 90,y: 80), end: CGPoint(x: 10,y: 20), size: CGSize(width: 100,height: 100)))
        #expect(region.x == 0.1 && region.y == 0.2 && region.width == 0.8 && region.height == 0.6)
        #expect(!ReviewRegion(x: .nan,y: 0,width: 1,height: 1).isValid)
        #expect(!ReviewRegion(x: 0.5,y: 0,width: 1,height: 1).isValid)
        #expect(ReviewRegion.selection(start: .zero,end: .zero,size: .zero) == nil)
    }

    @Test("Text differences preserve unchanged context and show removals and additions")
    func diff() {
        #expect(TextRevisionDiff.make(old: "A\nB\nC", new: "A\n新段落\nC") == "  A\n− B\n+ 新段落\n  C")
        #expect(TextRevisionDiff.make(old: "A\nA", new: "A") == "  A\n− A")
    }

    @Test("Text artifacts decode from Pi tool results and remain project scoped")
    @MainActor
    func eventAndScope() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let item = artifact(root, content: "result")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item))
        let event = try #require(PiRPCClient.parseEvent(["type":"tool_execution_end", "isError":false,
            "result":["content":[],"details":["personalPiTextArtifact":object]]]))
        #expect(event.textArtifact == item)
        let store = WorkbenchStore()
        store.configure(cwd: root.path)
        store.upsert(item)
        #expect(store.selected == item)
        store.configure(cwd: root.appendingPathComponent("other").path)
        store.upsert(item)
        #expect(store.artifacts.isEmpty)
    }

    @Test("Real Node bridge imports and reads a Markdown file without changing the source")
    func nativeBridge() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("input.md")
        try "# Results\nEvidence first.".write(to: source, atomically: true, encoding: .utf8)
        let response = try await Task.detached {
            try WorkbenchClient.execute(.init(action: "import",cwd: root.path,path: source.path))
        }.value
        let artifact = try #require(response.artifact)
        let read = try await Task.detached {
            try WorkbenchClient.execute(.init(action:"read",cwd:root.path,artifactId:artifact.artifactId,version:artifact.version))
        }.value
        #expect(read.content == "# Results\nEvidence first.")
        #expect(artifact.sourcePath != source.path)
        #expect(try String(contentsOf:source,encoding:.utf8) == read.content)
    }

    @Test("Figure annotations attach a valid PNG, survive project switching, and reach the RPC image field")
    @MainActor
    func imageRPCAndDraftScope() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = root.appendingPathComponent("A"), b = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: a,withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/workflow_peer.py")
        let client = PiRPCClient(executable:"/usr/bin/python3",arguments:["-u",fixture.path,root.path])
        let app = AppState(client:client,runtimeContext:PiRuntimeContext(environment:[:],dataRoot:root.appendingPathComponent("pi")),
            workspacePaths:[a.path,b.path],refreshAccounts:false)
        defer { client.stop() }
        let preview = a.appendingPathComponent("image.png")
        let ctx = try #require(CGContext(data:nil,width:100,height:50,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:100,height:50))
        let destination = try #require(CGImageDestinationCreateWithURL(preview as CFURL,"public.png" as CFString,1,nil))
        CGImageDestinationAddImage(destination,try #require(ctx.makeImage()),nil)
        #expect(CGImageDestinationFinalize(destination))
        let figure = FigureArtifact(schemaVersion:1,kind:"figure",id:"figure-v1",figureId:"figure",version:1,title:"Figure",
            sessionId:nil,cwd:a.path,createdAt:Date(),previewPath:preview.path,files:[.init(format:.png,path:preview.path)],
            widthMm:100,heightMm:50,dpi:300,validation:.init(passed:true,score:100,errors:[],warnings:[],checks:[]),intermediatesRetained:false)
        let review = try ArtifactReviewAttachment.figure(figure,region:.init(x:0.1,y:0.2,width:0.5,height:0.6),comment:"Move legend")
        #expect(throws: (any Error).self) {
            try ArtifactReviewAttachment.figure(figure, region: .init(x:0,y:0,width:1,height:1), comment:"Stale preview", expectedPreviewHash:"outdated")
        }
        let attachedImage = try #require(review.image)
        let png = try #require(Data(base64Encoded:attachedImage.data))
        #expect(CGImageSourceCreateWithData(png as CFData,nil) != nil)
        app.addReview(review)
        app.selectWorkspace(app.workspaces[1])
        #expect(app.reviewAttachments.isEmpty)
        app.selectWorkspace(app.workspaces[0])
        #expect(app.reviewAttachments.map(\.id) == [review.id])
        app.connectPi()
        for _ in 0..<500 {
            if app.sessionId != nil && client.pendingRequestCount == 0 { break }
            try await Task.sleep(for:.milliseconds(10))
        }
        #expect(app.sessionId != nil)
        app.composerText = "Apply my comment"
        app.sendPrompt()
        let record = root.appendingPathComponent("prompts.jsonl")
        for _ in 0..<500 {
            if FileManager.default.fileExists(atPath:record.path) { break }
            try await Task.sleep(for:.milliseconds(10))
        }
        let lines = try String(contentsOf:record,encoding:.utf8).split(separator:"\n")
        let lastLine = try #require(lines.last)
        let payload = try #require(JSONSerialization.jsonObject(with:Data(lastLine.utf8)) as? [String:Any])
        let images = try #require(payload["images"] as? [[String:Any]])
        #expect(images.count == 1)
        #expect(images.first?["data"] as? String == review.image?.data)
        #expect((payload["text"] as? String)?.contains("reviewBaseVersion") == true)
        #expect(app.reviewAttachments.isEmpty)
        #expect(app.messages.last(where:{$0.role == "user"})?.text.contains("Move legend") == true)
    }
}
