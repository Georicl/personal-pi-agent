import { writeFileSync } from "node:fs";

function writeResult(responsePath, result) {
	if (typeof responsePath !== "string" || !responsePath) return;
	writeFileSync(responsePath, JSON.stringify(result), "utf8");
}

export default function personalPiRuntimeExtension(pi) {
	pi.registerCommand("__personal_pi_navigate", {
		description: "Internal Personal Pi session-tree navigation",
		handler: async (args, ctx) => {
			const encoded = args.trim();
			if (!encoded) throw new Error("Missing session-tree navigation payload");

			let payload;
			try {
				payload = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
			} catch {
				throw new Error("Invalid session-tree navigation payload");
			}

			if (typeof payload.entryId !== "string" || !payload.entryId) {
				throw new Error("Missing session-tree entry ID");
			}

			try {
				await ctx.navigateTree(payload.entryId, {
					summarize: payload.summarize === true,
					customInstructions:
						typeof payload.customInstructions === "string" && payload.customInstructions
							? payload.customInstructions
							: undefined,
				});
				writeResult(payload.responsePath, { success: true });
			} catch (error) {
				writeResult(payload.responsePath, {
					success: false,
					error: error instanceof Error ? error.message : String(error),
				});
			}
		},
	});

	pi.registerCommand("__personal_pi_reload", {
		description: "Internal Personal Pi resource reload",
		handler: async (args, ctx) => {
			const encoded = args.trim();
			let payload = {};
			if (encoded) {
				try {
					payload = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
				} catch {
					throw new Error("Invalid resource reload payload");
				}
			}
			try {
				await ctx.reload();
				writeResult(payload.responsePath, { success: true });
			} catch (error) {
				writeResult(payload.responsePath, {
					success: false,
					error: error instanceof Error ? error.message : String(error),
				});
			}
		},
	});
}
