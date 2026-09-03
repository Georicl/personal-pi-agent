# Packages & Resources

Personal Pi exposes Pi's package and resource configuration through a native macOS page. The GUI does not maintain a second package registry: Pi remains the owner of installation directories, package source normalization, settings persistence, resource discovery, and Global/Project precedence.

## Scope

| GUI scope | Pi setting | Managed storage |
| --- | --- | --- |
| Global | `~/.pi/agent/settings.json` | `~/.pi/agent/npm/` and Pi's Global Git package directory |
| Project | `<project>/.pi/settings.json` | `<project>/.pi/npm/` and Pi's Project Git package directory |

Global Chat exposes only Global scope. A selected project exposes both scopes. In Project resource configuration, inherited Global resources are visible and can remain inherited, be explicitly loaded, or be explicitly unloaded.

## Package actions

- **Refresh** reads configured packages and resolved resources without installing missing sources.
- **Install** delegates to `DefaultPackageManager.installAndPersist` and accepts the same npm, Git, URL, and local-path sources as `pi install`.
- **Remove** delegates to `DefaultPackageManager.removeAndPersist` for the package's actual scope.
- **Update** delegates to `DefaultPackageManager.update`; updating all corresponds to `pi update --extensions` for the active Global and Project settings.

Pi packages execute with the current user's local permissions. The install confirmation communicates that boundary but does not add an agent tool-permission layer.

## Resource configuration

The page displays Extensions, Skills, Prompt Templates, and Themes returned by Pi. Global switches create Pi-compatible explicit load or unload rules. Project menus preserve Pi's three-state resource model:

- **Inherit**: remove the project-specific override.
- **Enabled**: explicitly load the resource in this project.
- **Disabled**: explicitly unload the resource in this project.

For a resource inherited from a Global package, Pi stores a project package delta with `autoload: false`. Returning the final override to Inherit removes the empty delta.

Additional resource paths are stored through Pi's `SettingsManager`; paths remain relative to the selected scope's Pi directory and support Pi glob and `+` / `-` / `!` rules.
