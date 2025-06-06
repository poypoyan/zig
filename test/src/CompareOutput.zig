//! This is the implementation of the test harness.
//! For the actual test cases, see test/compare_output.zig.

b: *std.Build,
step: *std.Build.Step,
test_index: usize,
test_filters: []const []const u8,
optimize_modes: []const OptimizeMode,

const Special = enum {
    None,
    Asm,
    RuntimeSafety,
};

const TestCase = struct {
    name: []const u8,
    sources: ArrayList(SourceFile),
    expected_output: []const u8,
    link_libc: bool,
    special: Special,
    cli_args: []const []const u8,

    const SourceFile = struct {
        filename: []const u8,
        source: []const u8,
    };

    pub fn addSourceFile(self: *TestCase, filename: []const u8, source: []const u8) void {
        self.sources.append(SourceFile{
            .filename = filename,
            .source = source,
        }) catch @panic("OOM");
    }

    pub fn setCommandLineArgs(self: *TestCase, args: []const []const u8) void {
        self.cli_args = args;
    }
};

pub fn createExtra(self: *CompareOutput, name: []const u8, source: []const u8, expected_output: []const u8, special: Special) TestCase {
    var tc = TestCase{
        .name = name,
        .sources = ArrayList(TestCase.SourceFile).init(self.b.allocator),
        .expected_output = expected_output,
        .link_libc = false,
        .special = special,
        .cli_args = &[_][]const u8{},
    };
    const root_src_name = if (special == Special.Asm) "source.s" else "source.zig";
    tc.addSourceFile(root_src_name, source);
    return tc;
}

pub fn create(self: *CompareOutput, name: []const u8, source: []const u8, expected_output: []const u8) TestCase {
    return createExtra(self, name, source, expected_output, Special.None);
}

pub fn addC(self: *CompareOutput, name: []const u8, source: []const u8, expected_output: []const u8) void {
    var tc = self.create(name, source, expected_output);
    tc.link_libc = true;
    self.addCase(tc);
}

pub fn add(self: *CompareOutput, name: []const u8, source: []const u8, expected_output: []const u8) void {
    const tc = self.create(name, source, expected_output);
    self.addCase(tc);
}

pub fn addAsm(self: *CompareOutput, name: []const u8, source: []const u8, expected_output: []const u8) void {
    const tc = self.createExtra(name, source, expected_output, Special.Asm);
    self.addCase(tc);
}

pub fn addRuntimeSafety(self: *CompareOutput, name: []const u8, source: []const u8) void {
    const tc = self.createExtra(name, source, undefined, Special.RuntimeSafety);
    self.addCase(tc);
}

pub fn addCase(self: *CompareOutput, case: TestCase) void {
    const b = self.b;

    const write_src = b.addWriteFiles();
    const first_src = case.sources.items[0];
    const first_file = write_src.add(first_src.filename, first_src.source);
    for (case.sources.items[1..]) |src_file| {
        _ = write_src.add(src_file.filename, src_file.source);
    }

    switch (case.special) {
        Special.Asm => {
            const annotated_case_name = b.fmt("run assemble-and-link {s}", .{
                case.name,
            });
            for (self.test_filters) |test_filter| {
                if (mem.indexOf(u8, annotated_case_name, test_filter)) |_| break;
            } else if (self.test_filters.len > 0) return;

            const exe = b.addExecutable(.{
                .name = "test",
                .root_module = b.createModule(.{
                    .root_source_file = null,
                    .target = b.graph.host,
                    .optimize = .Debug,
                }),
            });
            exe.root_module.addAssemblyFile(first_file);

            const run = b.addRunArtifact(exe);
            run.setName(annotated_case_name);
            run.addArgs(case.cli_args);
            run.expectStdOutEqual(case.expected_output);

            self.step.dependOn(&run.step);
        },
        Special.None => {
            for (self.optimize_modes) |optimize| {
                const annotated_case_name = b.fmt("run compare-output {s} ({s})", .{
                    case.name, @tagName(optimize),
                });
                for (self.test_filters) |test_filter| {
                    if (mem.indexOf(u8, annotated_case_name, test_filter)) |_| break;
                } else if (self.test_filters.len > 0) return;

                const exe = b.addExecutable(.{
                    .name = "test",
                    .root_module = b.createModule(.{
                        .root_source_file = first_file,
                        .optimize = optimize,
                        .target = b.graph.host,
                    }),
                });
                if (case.link_libc) exe.root_module.link_libc = true;

                const run = b.addRunArtifact(exe);
                run.setName(annotated_case_name);
                run.addArgs(case.cli_args);
                run.expectStdOutEqual(case.expected_output);

                self.step.dependOn(&run.step);
            }
        },
        Special.RuntimeSafety => {
            // TODO iterate over self.optimize_modes and test this in both
            // debug and release safe mode
            const annotated_case_name = b.fmt("run safety {s}", .{case.name});
            for (self.test_filters) |test_filter| {
                if (mem.indexOf(u8, annotated_case_name, test_filter)) |_| break;
            } else if (self.test_filters.len > 0) return;

            const exe = b.addExecutable(.{
                .name = "test",
                .root_module = b.createModule(.{
                    .root_source_file = first_file,
                    .target = b.graph.host,
                    .optimize = .Debug,
                }),
            });
            if (case.link_libc) exe.root_module.link_libc = true;

            const run = b.addRunArtifact(exe);
            run.setName(annotated_case_name);
            run.addArgs(case.cli_args);
            run.expectExitCode(126);

            self.step.dependOn(&run.step);
        },
    }
}

const CompareOutput = @This();
const std = @import("std");
const ArrayList = std.ArrayList;
const mem = std.mem;
const fs = std.fs;
const OptimizeMode = std.builtin.OptimizeMode;
