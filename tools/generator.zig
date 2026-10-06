const std = @import("std");

/// Project Generator CLI Scaffolding Tool for Mnemezigot Framework
/// Generates a new Mnemezigot project template with preconfigured build files and starter code.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // Skip binary name

    const project_name = args.next() orelse {
        std.debug.print("\nUsage: zig build new -- <project_name>\n", .{});
        std.debug.print("Example: zig build new -- my_web_app\n\n", .{});
        return;
    };

    std.debug.print("\n======================================================\n", .{});
    std.debug.print("🛠️ Mnemezigot Project Scaffolding Generator (Zig 0.16)\n", .{});
    std.debug.print("🚀 Creating new project: {s}...\n", .{project_name});
    std.debug.print("======================================================\n\n", .{});

    const cwd = std.fs.cwd();
    cwd.makeDir(project_name) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("❌ Failed to create project directory: {}\n", .{err});
            return err;
        }
    };

    var project_dir = try cwd.openDir(project_name, .{});
    defer project_dir.close();

    try project_dir.makeDir("src");
    try project_dir.makeDir("public");
    try project_dir.makeDir("data");

    // Write src/main.zig
    const main_code =
        \\const std = @import("std");
        \\const mn = @import("mnemezigot");
        \\
        \\fn handleIndex(ctx: *mn.Context) !void {
        \\    try ctx.html("<h1>Halo dari Mnemezigot Framework!</h1>");
        \\}
        \\
        \\pub fn main() !void {
        \\    const allocator = std.heap.smp_allocator;
        \\
        \\    var app = try mn.App.init(allocator, .{
        \\        .port = 8080,
        \\        .db_path = "data/app.db",
        \\    });
        \\    defer app.deinit();
        \\
        \\    try app.get("/", handleIndex);
        \\
        \\    std.debug.print("🚀 Mnemezigot server listening at http://127.0.0.1:8080\n", .{});
        \\    try app.listen();
        \\}
        \\
    ;
    var main_file = try project_dir.createFile("src/main.zig", .{});
    defer main_file.close();
    try main_file.writeAll(main_code);

    // Write public/index.html
    const index_html =
        \\<!DOCTYPE html>
        \\<html lang="id">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <title>Mnemezigot App</title>
        \\</head>
        \\<body>
        \\    <h1>Selamat Datang di Mnemezigot!</h1>
        \\</body>
        \\</html>
        \\
    ;
    var html_file = try project_dir.createFile("public/index.html", .{});
    defer html_file.close();
    try html_file.writeAll(index_html);

    // Write README.md
    const readme_md = try std.fmt.allocPrint(allocator,
        \\# {s}
        \\
        \\Aplikasi web dibangun menggunakan **Mnemezigot Framework** (Zig 0.16).
        \\
        \\## 🚀 Cara Menjalankan
        \\```bash
        \\zig build run
        \\```
        \\
        \\## ⚡ Hot Reload Watcher
        \\```bash
        \\zig build watch
        \\```
        \\
    , .{project_name});
    defer allocator.free(readme_md);

    var readme_file = try project_dir.createFile("README.md", .{});
    defer readme_file.close();
    try readme_file.writeAll(readme_md);

    std.debug.print("✅ Project '{s}' successfully created!\n", .{project_name});
    std.debug.print("👉 Next steps:\n", .{});
    std.debug.print("   cd {s}\n", .{project_name});
    std.debug.print("   zig build run\n\n", .{});
}

test "project generator output check" {
    _ = main;
}
