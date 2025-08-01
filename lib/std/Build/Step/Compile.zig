const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const assert = std.debug.assert;
const panic = std.debug.panic;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const Sha256 = std.crypto.hash.sha2.Sha256;
const Allocator = mem.Allocator;
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const PkgConfigPkg = std.Build.PkgConfigPkg;
const PkgConfigError = std.Build.PkgConfigError;
const RunError = std.Build.RunError;
const Module = std.Build.Module;
const InstallDir = std.Build.InstallDir;
const GeneratedFile = std.Build.GeneratedFile;
const Compile = @This();
const Path = std.Build.Cache.Path;

pub const base_id: Step.Id = .compile;

step: Step,
root_module: *Module,

name: []const u8,
linker_script: ?LazyPath = null,
version_script: ?LazyPath = null,
out_filename: []const u8,
out_lib_filename: []const u8,
linkage: ?std.builtin.LinkMode = null,
version: ?std.SemanticVersion,
kind: Kind,
major_only_filename: ?[]const u8,
name_only_filename: ?[]const u8,
formatted_panics: ?bool = null,
// keep in sync with src/link.zig:CompressDebugSections
compress_debug_sections: enum { none, zlib, zstd } = .none,
verbose_link: bool,
verbose_cc: bool,
bundle_compiler_rt: ?bool = null,
bundle_ubsan_rt: ?bool = null,
rdynamic: bool,
import_memory: bool = false,
export_memory: bool = false,
/// For WebAssembly targets, this will allow for undefined symbols to
/// be imported from the host environment.
import_symbols: bool = false,
import_table: bool = false,
export_table: bool = false,
initial_memory: ?u64 = null,
max_memory: ?u64 = null,
shared_memory: bool = false,
global_base: ?u64 = null,
/// Set via options; intended to be read-only after that.
zig_lib_dir: ?LazyPath,
exec_cmd_args: ?[]const ?[]const u8,
filters: []const []const u8,
test_runner: ?TestRunner,
wasi_exec_model: ?std.builtin.WasiExecModel = null,

installed_headers: ArrayList(HeaderInstallation),

/// This step is used to create an include tree that dependent modules can add to their include
/// search paths. Installed headers are copied to this step.
/// This step is created the first time a module links with this artifact and is not
/// created otherwise.
installed_headers_include_tree: ?*Step.WriteFile = null,

// keep in sync with src/Compilation.zig:RcIncludes
/// Behavior of automatic detection of include directories when compiling .rc files.
///  any: Use MSVC if available, fall back to MinGW.
///  msvc: Use MSVC include paths (must be present on the system).
///  gnu: Use MinGW include paths (distributed with Zig).
///  none: Do not use any autodetected include paths.
rc_includes: enum { any, msvc, gnu, none } = .any,

/// (Windows) .manifest file to embed in the compilation
/// Set via options; intended to be read-only after that.
win32_manifest: ?LazyPath = null,

installed_path: ?[]const u8,

/// Base address for an executable image.
image_base: ?u64 = null,

libc_file: ?LazyPath = null,

each_lib_rpath: ?bool = null,
/// On ELF targets, this will emit a link section called ".note.gnu.build-id"
/// which can be used to coordinate a stripped binary with its debug symbols.
/// As an example, the bloaty project refuses to work unless its inputs have
/// build ids, in order to prevent accidental mismatches.
/// The default is to not include this section because it slows down linking.
build_id: ?std.zig.BuildId = null,

/// Create a .eh_frame_hdr section and a PT_GNU_EH_FRAME segment in the ELF
/// file.
link_eh_frame_hdr: bool = false,
link_emit_relocs: bool = false,

/// Place every function in its own section so that unused ones may be
/// safely garbage-collected during the linking phase.
link_function_sections: bool = false,

/// Place every data in its own section so that unused ones may be
/// safely garbage-collected during the linking phase.
link_data_sections: bool = false,

/// Remove functions and data that are unreachable by the entry point or
/// exported symbols.
link_gc_sections: ?bool = null,

/// (Windows) Whether or not to enable ASLR. Maps to the /DYNAMICBASE[:NO] linker argument.
linker_dynamicbase: bool = true,

linker_allow_shlib_undefined: ?bool = null,

/// Allow version scripts to refer to undefined symbols.
linker_allow_undefined_version: ?bool = null,

// Enable (or disable) the new DT_RUNPATH tag in the dynamic section.
linker_enable_new_dtags: ?bool = null,

/// Permit read-only relocations in read-only segments. Disallowed by default.
link_z_notext: bool = false,

/// Force all relocations to be read-only after processing.
link_z_relro: bool = true,

/// Allow relocations to be lazily processed after load.
link_z_lazy: bool = false,

/// Common page size
link_z_common_page_size: ?u64 = null,

/// Maximum page size
link_z_max_page_size: ?u64 = null,

/// (Darwin) Install name for the dylib
install_name: ?[]const u8 = null,

/// (Darwin) Path to entitlements file
entitlements: ?[]const u8 = null,

/// (Darwin) Size of the pagezero segment.
pagezero_size: ?u64 = null,

/// (Darwin) Set size of the padding between the end of load commands
/// and start of `__TEXT,__text` section.
headerpad_size: ?u32 = null,

/// (Darwin) Automatically Set size of the padding between the end of load commands
/// and start of `__TEXT,__text` section to a value fitting all paths expanded to MAXPATHLEN.
headerpad_max_install_names: bool = false,

/// (Darwin) Remove dylibs that are unreachable by the entry point or exported symbols.
dead_strip_dylibs: bool = false,

/// (Darwin) Force load all members of static archives that implement an Objective-C class or category
force_load_objc: bool = false,

/// Whether local symbols should be discarded from the symbol table.
discard_local_symbols: bool = false,

/// Position Independent Executable
pie: ?bool = null,

/// Link Time Optimization mode
lto: ?std.zig.LtoMode = null,

dll_export_fns: ?bool = null,

subsystem: ?std.Target.SubSystem = null,

/// (Windows) When targeting the MinGW ABI, use the unicode entry point (wmain/wWinMain)
mingw_unicode_entry_point: bool = false,

/// How the linker must handle the entry point of the executable.
entry: Entry = .default,

/// List of symbols forced as undefined in the symbol table
/// thus forcing their resolution by the linker.
/// Corresponds to `-u <symbol>` for ELF/MachO and `/include:<symbol>` for COFF/PE.
force_undefined_symbols: std.StringHashMap(void),

/// Overrides the default stack size
stack_size: ?u64 = null,

/// Deprecated; prefer using `lto`.
want_lto: ?bool = null,

use_llvm: ?bool,
use_lld: ?bool,

/// Corresponds to the `-fallow-so-scripts` / `-fno-allow-so-scripts` CLI
/// flags, overriding the global user setting provided to the `zig build`
/// command.
///
/// The compiler defaults this value to off so that users whose system shared
/// libraries are all ELF files don't have to pay the cost of checking every
/// file to find out if it is a text file instead.
allow_so_scripts: ?bool = null,

/// This is an advanced setting that can change the intent of this Compile step.
/// If this value is non-null, it means that this Compile step exists to
/// check for compile errors and return *success* if they match, and failure
/// otherwise.
expect_errors: ?ExpectedCompileErrors = null,

emit_directory: ?*GeneratedFile,

generated_docs: ?*GeneratedFile,
generated_asm: ?*GeneratedFile,
generated_bin: ?*GeneratedFile,
generated_pdb: ?*GeneratedFile,
generated_implib: ?*GeneratedFile,
generated_llvm_bc: ?*GeneratedFile,
generated_llvm_ir: ?*GeneratedFile,
generated_h: ?*GeneratedFile,

/// The maximum number of distinct errors within a compilation step
/// Defaults to `std.math.maxInt(u16)`
error_limit: ?u32 = null,

/// Computed during make().
is_linking_libc: bool = false,
/// Computed during make().
is_linking_libcpp: bool = false,

/// Populated during the make phase when there is a long-lived compiler process.
/// Managed by the build runner, not user build script.
zig_process: ?*Step.ZigProcess,

/// Enables coverage instrumentation that is only useful if you are using third
/// party fuzzers that depend on it. Otherwise, slows down the instrumented
/// binary with unnecessary function calls.
///
/// This kind of coverage instrumentation is used by AFLplusplus v4.21c,
/// however, modern fuzzers - including Zig - have switched to using "inline
/// 8-bit counters" or "inline bool flag" which incurs only a single
/// instruction for coverage, along with "trace cmp" which instruments
/// comparisons and reports the operands.
///
/// To instead enable fuzz testing instrumentation on a compilation using Zig's
/// builtin fuzzer, see the `fuzz` flag in `Module`.
sanitize_coverage_trace_pc_guard: ?bool = null,

pub const ExpectedCompileErrors = union(enum) {
    contains: []const u8,
    exact: []const []const u8,
    starts_with: []const u8,
    stderr_contains: []const u8,
};

pub const Entry = union(enum) {
    /// Let the compiler decide whether to make an entry point and what to name
    /// it.
    default,
    /// The executable will have no entry point.
    disabled,
    /// The executable will have an entry point with the default symbol name.
    enabled,
    /// The executable will have an entry point with the specified symbol name.
    symbol_name: []const u8,
};

pub const Options = struct {
    name: []const u8,
    root_module: *Module,
    kind: Kind,
    linkage: ?std.builtin.LinkMode = null,
    version: ?std.SemanticVersion = null,
    max_rss: usize = 0,
    filters: []const []const u8 = &.{},
    test_runner: ?TestRunner = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?LazyPath = null,
    /// Embed a `.manifest` file in the compilation if the object format supports it.
    /// https://learn.microsoft.com/en-us/windows/win32/sbscs/manifest-files-reference
    /// Manifest files must have the extension `.manifest`.
    /// Can be set regardless of target. The `.manifest` file will be ignored
    /// if the target object format does not support embedded manifests.
    win32_manifest: ?LazyPath = null,
};

pub const Kind = enum {
    exe,
    lib,
    obj,
    @"test",
    test_obj,

    pub fn isTest(kind: Kind) bool {
        return switch (kind) {
            .exe, .lib, .obj => false,
            .@"test", .test_obj => true,
        };
    }
};

pub const HeaderInstallation = union(enum) {
    file: File,
    directory: Directory,

    pub const File = struct {
        source: LazyPath,
        dest_rel_path: []const u8,

        pub fn dupe(file: File, b: *std.Build) File {
            return .{
                .source = file.source.dupe(b),
                .dest_rel_path = b.dupePath(file.dest_rel_path),
            };
        }
    };

    pub const Directory = struct {
        source: LazyPath,
        dest_rel_path: []const u8,
        options: Directory.Options,

        pub const Options = struct {
            /// File paths that end in any of these suffixes will be excluded from installation.
            exclude_extensions: []const []const u8 = &.{},
            /// Only file paths that end in any of these suffixes will be included in installation.
            /// `null` means that all suffixes will be included.
            /// `exclude_extensions` takes precedence over `include_extensions`.
            include_extensions: ?[]const []const u8 = &.{".h"},

            pub fn dupe(opts: Directory.Options, b: *std.Build) Directory.Options {
                return .{
                    .exclude_extensions = b.dupeStrings(opts.exclude_extensions),
                    .include_extensions = if (opts.include_extensions) |incs| b.dupeStrings(incs) else null,
                };
            }
        };

        pub fn dupe(dir: Directory, b: *std.Build) Directory {
            return .{
                .source = dir.source.dupe(b),
                .dest_rel_path = b.dupePath(dir.dest_rel_path),
                .options = dir.options.dupe(b),
            };
        }
    };

    pub fn getSource(installation: HeaderInstallation) LazyPath {
        return switch (installation) {
            inline .file, .directory => |x| x.source,
        };
    }

    pub fn dupe(installation: HeaderInstallation, b: *std.Build) HeaderInstallation {
        return switch (installation) {
            .file => |f| .{ .file = f.dupe(b) },
            .directory => |d| .{ .directory = d.dupe(b) },
        };
    }
};

pub const TestRunner = struct {
    path: LazyPath,
    /// Test runners can either be "simple", running tests when spawned and terminating when the
    /// tests are complete, or they can use `std.zig.Server` over stdio to interact more closely
    /// with the build system.
    mode: enum { simple, server },
};

pub fn create(owner: *std.Build, options: Options) *Compile {
    const name = owner.dupe(options.name);
    if (mem.indexOf(u8, name, "/") != null or mem.indexOf(u8, name, "\\") != null) {
        panic("invalid name: '{s}'. It looks like a file path, but it is supposed to be the library or application name.", .{name});
    }

    const resolved_target = options.root_module.resolved_target orelse
        @panic("the root Module of a Compile step must be created with a known 'target' field");
    const target = &resolved_target.result;

    const step_name = owner.fmt("compile {s} {s} {s}", .{
        // Avoid the common case of the step name looking like "compile test test".
        if (options.kind.isTest() and mem.eql(u8, name, "test"))
            @tagName(options.kind)
        else
            owner.fmt("{s} {s}", .{ @tagName(options.kind), name }),
        @tagName(options.root_module.optimize orelse .Debug),
        resolved_target.query.zigTriple(owner.allocator) catch @panic("OOM"),
    });

    const out_filename = std.zig.binNameAlloc(owner.allocator, .{
        .root_name = name,
        .target = target,
        .output_mode = switch (options.kind) {
            .lib => .Lib,
            .obj, .test_obj => .Obj,
            .exe, .@"test" => .Exe,
        },
        .link_mode = options.linkage,
        .version = options.version,
    }) catch @panic("OOM");

    const compile = owner.allocator.create(Compile) catch @panic("OOM");
    compile.* = .{
        .root_module = options.root_module,
        .verbose_link = false,
        .verbose_cc = false,
        .linkage = options.linkage,
        .kind = options.kind,
        .name = name,
        .step = .init(.{
            .id = base_id,
            .name = step_name,
            .owner = owner,
            .makeFn = make,
            .max_rss = options.max_rss,
        }),
        .version = options.version,
        .out_filename = out_filename,
        .out_lib_filename = undefined,
        .major_only_filename = null,
        .name_only_filename = null,
        .installed_headers = ArrayList(HeaderInstallation).init(owner.allocator),
        .zig_lib_dir = null,
        .exec_cmd_args = null,
        .filters = options.filters,
        .test_runner = null, // set below
        .rdynamic = false,
        .installed_path = null,
        .force_undefined_symbols = StringHashMap(void).init(owner.allocator),

        .emit_directory = null,
        .generated_docs = null,
        .generated_asm = null,
        .generated_bin = null,
        .generated_pdb = null,
        .generated_implib = null,
        .generated_llvm_bc = null,
        .generated_llvm_ir = null,
        .generated_h = null,

        .use_llvm = options.use_llvm,
        .use_lld = options.use_lld,

        .zig_process = null,
    };

    if (options.zig_lib_dir) |lp| {
        compile.zig_lib_dir = lp.dupe(compile.step.owner);
        lp.addStepDependencies(&compile.step);
    }

    if (options.test_runner) |runner| {
        compile.test_runner = .{
            .path = runner.path.dupe(compile.step.owner),
            .mode = runner.mode,
        };
        runner.path.addStepDependencies(&compile.step);
    }

    // Only the PE/COFF format has a Resource Table which is where the manifest
    // gets embedded, so for any other target the manifest file is just ignored.
    if (target.ofmt == .coff) {
        if (options.win32_manifest) |lp| {
            compile.win32_manifest = lp.dupe(compile.step.owner);
            lp.addStepDependencies(&compile.step);
        }
    }

    if (compile.kind == .lib) {
        if (compile.linkage != null and compile.linkage.? == .static) {
            compile.out_lib_filename = compile.out_filename;
        } else if (compile.version) |version| {
            if (target.os.tag.isDarwin()) {
                compile.major_only_filename = owner.fmt("lib{s}.{d}.dylib", .{
                    compile.name,
                    version.major,
                });
                compile.name_only_filename = owner.fmt("lib{s}.dylib", .{compile.name});
                compile.out_lib_filename = compile.out_filename;
            } else if (target.os.tag == .windows) {
                compile.out_lib_filename = owner.fmt("{s}.lib", .{compile.name});
            } else {
                compile.major_only_filename = owner.fmt("lib{s}.so.{d}", .{ compile.name, version.major });
                compile.name_only_filename = owner.fmt("lib{s}.so", .{compile.name});
                compile.out_lib_filename = compile.out_filename;
            }
        } else {
            if (target.os.tag.isDarwin()) {
                compile.out_lib_filename = compile.out_filename;
            } else if (target.os.tag == .windows) {
                compile.out_lib_filename = owner.fmt("{s}.lib", .{compile.name});
            } else {
                compile.out_lib_filename = compile.out_filename;
            }
        }
    }

    return compile;
}

/// Marks the specified header for installation alongside this artifact.
/// When a module links with this artifact, all headers marked for installation are added to that
/// module's include search path.
pub fn installHeader(cs: *Compile, source: LazyPath, dest_rel_path: []const u8) void {
    const b = cs.step.owner;
    const installation: HeaderInstallation = .{ .file = .{
        .source = source.dupe(b),
        .dest_rel_path = b.dupePath(dest_rel_path),
    } };
    cs.installed_headers.append(installation) catch @panic("OOM");
    cs.addHeaderInstallationToIncludeTree(installation);
    installation.getSource().addStepDependencies(&cs.step);
}

/// Marks headers from the specified directory for installation alongside this artifact.
/// When a module links with this artifact, all headers marked for installation are added to that
/// module's include search path.
pub fn installHeadersDirectory(
    cs: *Compile,
    source: LazyPath,
    dest_rel_path: []const u8,
    options: HeaderInstallation.Directory.Options,
) void {
    const b = cs.step.owner;
    const installation: HeaderInstallation = .{ .directory = .{
        .source = source.dupe(b),
        .dest_rel_path = b.dupePath(dest_rel_path),
        .options = options.dupe(b),
    } };
    cs.installed_headers.append(installation) catch @panic("OOM");
    cs.addHeaderInstallationToIncludeTree(installation);
    installation.getSource().addStepDependencies(&cs.step);
}

/// Marks the specified config header for installation alongside this artifact.
/// When a module links with this artifact, all headers marked for installation are added to that
/// module's include search path.
pub fn installConfigHeader(cs: *Compile, config_header: *Step.ConfigHeader) void {
    cs.installHeader(config_header.getOutput(), config_header.include_path);
}

/// Forwards all headers marked for installation from `lib` to this artifact.
/// When a module links with this artifact, all headers marked for installation are added to that
/// module's include search path.
pub fn installLibraryHeaders(cs: *Compile, lib: *Compile) void {
    assert(lib.kind == .lib);
    for (lib.installed_headers.items) |installation| {
        const installation_copy = installation.dupe(lib.step.owner);
        cs.installed_headers.append(installation_copy) catch @panic("OOM");
        cs.addHeaderInstallationToIncludeTree(installation_copy);
        installation_copy.getSource().addStepDependencies(&cs.step);
    }
}

fn addHeaderInstallationToIncludeTree(cs: *Compile, installation: HeaderInstallation) void {
    if (cs.installed_headers_include_tree) |wf| switch (installation) {
        .file => |file| {
            _ = wf.addCopyFile(file.source, file.dest_rel_path);
        },
        .directory => |dir| {
            _ = wf.addCopyDirectory(dir.source, dir.dest_rel_path, .{
                .exclude_extensions = dir.options.exclude_extensions,
                .include_extensions = dir.options.include_extensions,
            });
        },
    };
}

pub fn getEmittedIncludeTree(cs: *Compile) LazyPath {
    if (cs.installed_headers_include_tree) |wf| return wf.getDirectory();
    const b = cs.step.owner;
    const wf = b.addWriteFiles();
    cs.installed_headers_include_tree = wf;
    for (cs.installed_headers.items) |installation| {
        cs.addHeaderInstallationToIncludeTree(installation);
    }
    // The compile step itself does not need to depend on the write files step,
    // only dependent modules do.
    return wf.getDirectory();
}

pub fn addObjCopy(cs: *Compile, options: Step.ObjCopy.Options) *Step.ObjCopy {
    const b = cs.step.owner;
    var copy = options;
    if (copy.basename == null) {
        if (options.format) |f| {
            copy.basename = b.fmt("{s}.{s}", .{ cs.name, @tagName(f) });
        } else {
            copy.basename = cs.name;
        }
    }
    return b.addObjCopy(cs.getEmittedBin(), copy);
}

pub fn checkObject(compile: *Compile) *Step.CheckObject {
    return Step.CheckObject.create(compile.step.owner, compile.getEmittedBin(), compile.rootModuleTarget().ofmt);
}

pub fn setLinkerScript(compile: *Compile, source: LazyPath) void {
    const b = compile.step.owner;
    compile.linker_script = source.dupe(b);
    source.addStepDependencies(&compile.step);
}

pub fn setVersionScript(compile: *Compile, source: LazyPath) void {
    const b = compile.step.owner;
    compile.version_script = source.dupe(b);
    source.addStepDependencies(&compile.step);
}

pub fn forceUndefinedSymbol(compile: *Compile, symbol_name: []const u8) void {
    const b = compile.step.owner;
    compile.force_undefined_symbols.put(b.dupe(symbol_name), {}) catch @panic("OOM");
}

/// Returns whether the library, executable, or object depends on a particular system library.
/// Includes transitive dependencies.
pub fn dependsOnSystemLibrary(compile: *Compile, name: []const u8) bool {
    var is_linking_libc = false;
    var is_linking_libcpp = false;

    for (compile.getCompileDependencies(true)) |some_compile| {
        for (some_compile.root_module.getGraph().modules) |mod| {
            for (mod.link_objects.items) |lo| {
                switch (lo) {
                    .system_lib => |lib| if (mem.eql(u8, lib.name, name)) return true,
                    else => {},
                }
            }
            if (mod.link_libc orelse false) is_linking_libc = true;
            if (mod.link_libcpp orelse false) is_linking_libcpp = true;
        }
    }

    const target = compile.rootModuleTarget();

    if (std.zig.target.isLibCLibName(target, name)) {
        return is_linking_libc;
    }

    if (std.zig.target.isLibCxxLibName(target, name)) {
        return is_linking_libcpp;
    }

    return false;
}

pub fn isDynamicLibrary(compile: *const Compile) bool {
    return compile.kind == .lib and compile.linkage == .dynamic;
}

pub fn isStaticLibrary(compile: *const Compile) bool {
    return compile.kind == .lib and compile.linkage != .dynamic;
}

pub fn isDll(compile: *Compile) bool {
    return compile.isDynamicLibrary() and compile.rootModuleTarget().os.tag == .windows;
}

pub fn producesPdbFile(compile: *Compile) bool {
    const target = compile.rootModuleTarget();
    // TODO: Is this right? Isn't PDB for *any* PE/COFF file?
    // TODO: just share this logic with the compiler, silly!
    switch (target.os.tag) {
        .windows, .uefi => {},
        else => return false,
    }
    if (target.ofmt == .c) return false;
    if (compile.use_llvm == false) return false;
    if (compile.root_module.strip == true or
        (compile.root_module.strip == null and compile.root_module.optimize == .ReleaseSmall))
    {
        return false;
    }
    return compile.isDynamicLibrary() or compile.kind == .exe or compile.kind == .@"test";
}

pub fn producesImplib(compile: *Compile) bool {
    return compile.isDll();
}

/// Deprecated; use `compile.root_module.link_libc = true` instead.
/// To be removed after 0.15.0 is tagged.
pub fn linkLibC(compile: *Compile) void {
    compile.root_module.link_libc = true;
}

/// Deprecated; use `compile.root_module.link_libcpp = true` instead.
/// To be removed after 0.15.0 is tagged.
pub fn linkLibCpp(compile: *Compile) void {
    compile.root_module.link_libcpp = true;
}

const PkgConfigResult = struct {
    cflags: []const []const u8,
    libs: []const []const u8,
};

/// Run pkg-config for the given library name and parse the output, returning the arguments
/// that should be passed to zig to link the given library.
fn runPkgConfig(compile: *Compile, lib_name: []const u8) !PkgConfigResult {
    const wl_rpath_prefix = "-Wl,-rpath,";

    const b = compile.step.owner;
    const pkg_name = match: {
        // First we have to map the library name to pkg config name. Unfortunately,
        // there are several examples where this is not straightforward:
        // -lSDL2 -> pkg-config sdl2
        // -lgdk-3 -> pkg-config gdk-3.0
        // -latk-1.0 -> pkg-config atk
        // -lpulse -> pkg-config libpulse
        const pkgs = try getPkgConfigList(b);

        // Exact match means instant winner.
        for (pkgs) |pkg| {
            if (mem.eql(u8, pkg.name, lib_name)) {
                break :match pkg.name;
            }
        }

        // Next we'll try ignoring case.
        for (pkgs) |pkg| {
            if (std.ascii.eqlIgnoreCase(pkg.name, lib_name)) {
                break :match pkg.name;
            }
        }

        // Prefixed "lib" or suffixed ".0".
        for (pkgs) |pkg| {
            if (std.ascii.indexOfIgnoreCase(pkg.name, lib_name)) |pos| {
                const prefix = pkg.name[0..pos];
                const suffix = pkg.name[pos + lib_name.len ..];
                if (prefix.len > 0 and !mem.eql(u8, prefix, "lib")) continue;
                if (suffix.len > 0 and !mem.eql(u8, suffix, ".0")) continue;
                break :match pkg.name;
            }
        }

        // Trimming "-1.0".
        if (mem.endsWith(u8, lib_name, "-1.0")) {
            const trimmed_lib_name = lib_name[0 .. lib_name.len - "-1.0".len];
            for (pkgs) |pkg| {
                if (std.ascii.eqlIgnoreCase(pkg.name, trimmed_lib_name)) {
                    break :match pkg.name;
                }
            }
        }

        return error.PackageNotFound;
    };

    var code: u8 = undefined;
    const pkg_config_exe = b.graph.env_map.get("PKG_CONFIG") orelse "pkg-config";
    const stdout = if (b.runAllowFail(&[_][]const u8{
        pkg_config_exe,
        pkg_name,
        "--cflags",
        "--libs",
    }, &code, .Ignore)) |stdout| stdout else |err| switch (err) {
        error.ProcessTerminated => return error.PkgConfigCrashed,
        error.ExecNotSupported => return error.PkgConfigFailed,
        error.ExitCodeFailure => return error.PkgConfigFailed,
        error.FileNotFound => return error.PkgConfigNotInstalled,
        else => return err,
    };

    var zig_cflags = ArrayList([]const u8).init(b.allocator);
    defer zig_cflags.deinit();
    var zig_libs = ArrayList([]const u8).init(b.allocator);
    defer zig_libs.deinit();

    var arg_it = mem.tokenizeAny(u8, stdout, " \r\n\t");
    while (arg_it.next()) |arg| {
        if (mem.eql(u8, arg, "-I")) {
            const dir = arg_it.next() orelse return error.PkgConfigInvalidOutput;
            try zig_cflags.appendSlice(&[_][]const u8{ "-I", dir });
        } else if (mem.startsWith(u8, arg, "-I")) {
            try zig_cflags.append(arg);
        } else if (mem.eql(u8, arg, "-L")) {
            const dir = arg_it.next() orelse return error.PkgConfigInvalidOutput;
            try zig_libs.appendSlice(&[_][]const u8{ "-L", dir });
        } else if (mem.startsWith(u8, arg, "-L")) {
            try zig_libs.append(arg);
        } else if (mem.eql(u8, arg, "-l")) {
            const lib = arg_it.next() orelse return error.PkgConfigInvalidOutput;
            try zig_libs.appendSlice(&[_][]const u8{ "-l", lib });
        } else if (mem.startsWith(u8, arg, "-l")) {
            try zig_libs.append(arg);
        } else if (mem.eql(u8, arg, "-D")) {
            const macro = arg_it.next() orelse return error.PkgConfigInvalidOutput;
            try zig_cflags.appendSlice(&[_][]const u8{ "-D", macro });
        } else if (mem.startsWith(u8, arg, "-D")) {
            try zig_cflags.append(arg);
        } else if (mem.startsWith(u8, arg, wl_rpath_prefix)) {
            try zig_cflags.appendSlice(&[_][]const u8{ "-rpath", arg[wl_rpath_prefix.len..] });
        } else if (b.debug_pkg_config) {
            return compile.step.fail("unknown pkg-config flag '{s}'", .{arg});
        }
    }

    return .{
        .cflags = try zig_cflags.toOwnedSlice(),
        .libs = try zig_libs.toOwnedSlice(),
    };
}

/// Deprecated; use `compile.root_module.linkSystemLibrary(name, .{})` instead.
/// To be removed after 0.15.0 is tagged.
pub fn linkSystemLibrary(compile: *Compile, name: []const u8) void {
    return compile.root_module.linkSystemLibrary(name, .{});
}

/// Deprecated; use `compile.root_module.linkSystemLibrary(name, options)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn linkSystemLibrary2(
    compile: *Compile,
    name: []const u8,
    options: Module.LinkSystemLibraryOptions,
) void {
    return compile.root_module.linkSystemLibrary(name, options);
}

/// Deprecated; use `c.root_module.linkFramework(name, .{})` instead.
/// To be removed after 0.15.0 is tagged.
pub fn linkFramework(c: *Compile, name: []const u8) void {
    c.root_module.linkFramework(name, .{});
}

/// Deprecated; use `compile.root_module.addCSourceFiles(options)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addCSourceFiles(compile: *Compile, options: Module.AddCSourceFilesOptions) void {
    compile.root_module.addCSourceFiles(options);
}

/// Deprecated; use `compile.root_module.addCSourceFile(source)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addCSourceFile(compile: *Compile, source: Module.CSourceFile) void {
    compile.root_module.addCSourceFile(source);
}

/// Deprecated; use `compile.root_module.addWin32ResourceFile(source)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addWin32ResourceFile(compile: *Compile, source: Module.RcSourceFile) void {
    compile.root_module.addWin32ResourceFile(source);
}

pub fn setVerboseLink(compile: *Compile, value: bool) void {
    compile.verbose_link = value;
}

pub fn setVerboseCC(compile: *Compile, value: bool) void {
    compile.verbose_cc = value;
}

pub fn setLibCFile(compile: *Compile, libc_file: ?LazyPath) void {
    const b = compile.step.owner;
    if (libc_file) |f| {
        compile.libc_file = f.dupe(b);
        f.addStepDependencies(&compile.step);
    } else {
        compile.libc_file = null;
    }
}

fn getEmittedFileGeneric(compile: *Compile, output_file: *?*GeneratedFile) LazyPath {
    if (output_file.*) |file| return .{ .generated = .{ .file = file } };
    const arena = compile.step.owner.allocator;
    const generated_file = arena.create(GeneratedFile) catch @panic("OOM");
    generated_file.* = .{ .step = &compile.step };
    output_file.* = generated_file;
    return .{ .generated = .{ .file = generated_file } };
}

/// Returns the path to the directory that contains the emitted binary file.
pub fn getEmittedBinDirectory(compile: *Compile) LazyPath {
    _ = compile.getEmittedBin();
    return compile.getEmittedFileGeneric(&compile.emit_directory);
}

/// Returns the path to the generated executable, library or object file.
/// To run an executable built with zig build, use `run`, or create an install step and invoke it.
pub fn getEmittedBin(compile: *Compile) LazyPath {
    return compile.getEmittedFileGeneric(&compile.generated_bin);
}

/// Returns the path to the generated import library.
/// This function can only be called for libraries.
pub fn getEmittedImplib(compile: *Compile) LazyPath {
    assert(compile.kind == .lib);
    return compile.getEmittedFileGeneric(&compile.generated_implib);
}

/// Returns the path to the generated header file.
/// This function can only be called for libraries or objects.
pub fn getEmittedH(compile: *Compile) LazyPath {
    assert(compile.kind != .exe and compile.kind != .@"test");
    return compile.getEmittedFileGeneric(&compile.generated_h);
}

/// Returns the generated PDB file.
/// If the compilation does not produce a PDB file, this causes a FileNotFound error
/// at build time.
pub fn getEmittedPdb(compile: *Compile) LazyPath {
    _ = compile.getEmittedBin();
    return compile.getEmittedFileGeneric(&compile.generated_pdb);
}

/// Returns the path to the generated documentation directory.
pub fn getEmittedDocs(compile: *Compile) LazyPath {
    return compile.getEmittedFileGeneric(&compile.generated_docs);
}

/// Returns the path to the generated assembly code.
pub fn getEmittedAsm(compile: *Compile) LazyPath {
    return compile.getEmittedFileGeneric(&compile.generated_asm);
}

/// Returns the path to the generated LLVM IR.
pub fn getEmittedLlvmIr(compile: *Compile) LazyPath {
    return compile.getEmittedFileGeneric(&compile.generated_llvm_ir);
}

/// Returns the path to the generated LLVM BC.
pub fn getEmittedLlvmBc(compile: *Compile) LazyPath {
    return compile.getEmittedFileGeneric(&compile.generated_llvm_bc);
}

/// Deprecated; use `compile.root_module.addAssemblyFile(source)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addAssemblyFile(compile: *Compile, source: LazyPath) void {
    compile.root_module.addAssemblyFile(source);
}

/// Deprecated; use `compile.root_module.addObjectFile(source)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addObjectFile(compile: *Compile, source: LazyPath) void {
    compile.root_module.addObjectFile(source);
}

/// Deprecated; use `compile.root_module.addObject(object)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addObject(compile: *Compile, object: *Compile) void {
    compile.root_module.addObject(object);
}

/// Deprecated; use `compile.root_module.linkLibrary(library)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn linkLibrary(compile: *Compile, library: *Compile) void {
    compile.root_module.linkLibrary(library);
}

/// Deprecated; use `compile.root_module.addAfterIncludePath(lazy_path)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addAfterIncludePath(compile: *Compile, lazy_path: LazyPath) void {
    compile.root_module.addAfterIncludePath(lazy_path);
}

/// Deprecated; use `compile.root_module.addSystemIncludePath(lazy_path)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addSystemIncludePath(compile: *Compile, lazy_path: LazyPath) void {
    compile.root_module.addSystemIncludePath(lazy_path);
}

/// Deprecated; use `compile.root_module.addIncludePath(lazy_path)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addIncludePath(compile: *Compile, lazy_path: LazyPath) void {
    compile.root_module.addIncludePath(lazy_path);
}

/// Deprecated; use `compile.root_module.addConfigHeader(config_header)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addConfigHeader(compile: *Compile, config_header: *Step.ConfigHeader) void {
    compile.root_module.addConfigHeader(config_header);
}

/// Deprecated; use `compile.root_module.addEmbedPath(lazy_path)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addEmbedPath(compile: *Compile, lazy_path: LazyPath) void {
    compile.root_module.addEmbedPath(lazy_path);
}

/// Deprecated; use `compile.root_module.addLibraryPath(directory_path)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addLibraryPath(compile: *Compile, directory_path: LazyPath) void {
    compile.root_module.addLibraryPath(directory_path);
}

/// Deprecated; use `compile.root_module.addRPath(directory_path)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addRPath(compile: *Compile, directory_path: LazyPath) void {
    compile.root_module.addRPath(directory_path);
}

/// Deprecated; use `compile.root_module.addSystemFrameworkPath(directory_path)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addSystemFrameworkPath(compile: *Compile, directory_path: LazyPath) void {
    compile.root_module.addSystemFrameworkPath(directory_path);
}

/// Deprecated; use `compile.root_module.addFrameworkPath(directory_path)` instead.
/// To be removed after 0.15.0 is tagged.
pub fn addFrameworkPath(compile: *Compile, directory_path: LazyPath) void {
    compile.root_module.addFrameworkPath(directory_path);
}

pub fn setExecCmd(compile: *Compile, args: []const ?[]const u8) void {
    const b = compile.step.owner;
    assert(compile.kind == .@"test");
    const duped_args = b.allocator.alloc(?[]u8, args.len) catch @panic("OOM");
    for (args, 0..) |arg, i| {
        duped_args[i] = if (arg) |a| b.dupe(a) else null;
    }
    compile.exec_cmd_args = duped_args;
}

const CliNamedModules = struct {
    modules: std.AutoArrayHashMapUnmanaged(*Module, void),
    names: std.StringArrayHashMapUnmanaged(void),

    /// Traverse the whole dependency graph and give every module a unique
    /// name, ideally one named after what it's called somewhere in the graph.
    /// It will help here to have both a mapping from module to name and a set
    /// of all the currently-used names.
    fn init(arena: Allocator, root_module: *Module) Allocator.Error!CliNamedModules {
        var compile: CliNamedModules = .{
            .modules = .{},
            .names = .{},
        };
        const graph = root_module.getGraph();
        {
            assert(graph.modules[0] == root_module);
            try compile.modules.put(arena, root_module, {});
            try compile.names.put(arena, "root", {});
        }
        for (graph.modules[1..], graph.names[1..]) |mod, orig_name| {
            var name = orig_name;
            var n: usize = 0;
            while (true) {
                const gop = try compile.names.getOrPut(arena, name);
                if (!gop.found_existing) {
                    try compile.modules.putNoClobber(arena, mod, {});
                    break;
                }
                name = try std.fmt.allocPrint(arena, "{s}{d}", .{ orig_name, n });
                n += 1;
            }
        }
        return compile;
    }
};

fn getGeneratedFilePath(compile: *Compile, comptime tag_name: []const u8, asking_step: ?*Step) []const u8 {
    const maybe_path: ?*GeneratedFile = @field(compile, tag_name);

    const generated_file = maybe_path orelse {
        const w = std.debug.lockStderrWriter(&.{});
        std.Build.dumpBadGetPathHelp(&compile.step, w, .detect(.stderr()), compile.step.owner, asking_step) catch {};
        std.debug.unlockStderrWriter();
        @panic("missing emit option for " ++ tag_name);
    };

    const path = generated_file.path orelse {
        const w = std.debug.lockStderrWriter(&.{});
        std.Build.dumpBadGetPathHelp(&compile.step, w, .detect(.stderr()), compile.step.owner, asking_step) catch {};
        std.debug.unlockStderrWriter();
        @panic(tag_name ++ " is null. Is there a missing step dependency?");
    };

    return path;
}

fn getZigArgs(compile: *Compile, fuzz: bool) ![][]const u8 {
    const step = &compile.step;
    const b = step.owner;
    const arena = b.allocator;

    var zig_args = ArrayList([]const u8).init(arena);
    defer zig_args.deinit();

    try zig_args.append(b.graph.zig_exe);

    const cmd = switch (compile.kind) {
        .lib => "build-lib",
        .exe => "build-exe",
        .obj => "build-obj",
        .@"test" => "test",
        .test_obj => "test-obj",
    };
    try zig_args.append(cmd);

    if (b.reference_trace) |some| {
        try zig_args.append(try std.fmt.allocPrint(arena, "-freference-trace={d}", .{some}));
    }
    try addFlag(&zig_args, "allow-so-scripts", compile.allow_so_scripts orelse b.graph.allow_so_scripts);

    try addFlag(&zig_args, "llvm", compile.use_llvm);
    try addFlag(&zig_args, "lld", compile.use_lld);

    if (compile.root_module.resolved_target.?.query.ofmt) |ofmt| {
        try zig_args.append(try std.fmt.allocPrint(arena, "-ofmt={s}", .{@tagName(ofmt)}));
    }

    switch (compile.entry) {
        .default => {},
        .disabled => try zig_args.append("-fno-entry"),
        .enabled => try zig_args.append("-fentry"),
        .symbol_name => |entry_name| {
            try zig_args.append(try std.fmt.allocPrint(arena, "-fentry={s}", .{entry_name}));
        },
    }

    {
        var symbol_it = compile.force_undefined_symbols.keyIterator();
        while (symbol_it.next()) |symbol_name| {
            try zig_args.append("--force_undefined");
            try zig_args.append(symbol_name.*);
        }
    }

    if (compile.stack_size) |stack_size| {
        try zig_args.append("--stack");
        try zig_args.append(try std.fmt.allocPrint(arena, "{}", .{stack_size}));
    }

    if (fuzz) {
        try zig_args.append("-ffuzz");
    }

    {
        // Stores system libraries that have already been seen for at least one
        // module, along with any arguments that need to be passed to the
        // compiler for each module individually.
        var seen_system_libs: std.StringHashMapUnmanaged([]const []const u8) = .empty;
        var frameworks: std.StringArrayHashMapUnmanaged(Module.LinkFrameworkOptions) = .empty;

        var prev_has_cflags = false;
        var prev_has_rcflags = false;
        var prev_search_strategy: Module.SystemLib.SearchStrategy = .paths_first;
        var prev_preferred_link_mode: std.builtin.LinkMode = .dynamic;
        // Track the number of positional arguments so that a nice error can be
        // emitted if there is nothing to link.
        var total_linker_objects: usize = @intFromBool(compile.root_module.root_source_file != null);

        // Fully recursive iteration including dynamic libraries to detect
        // libc and libc++ linkage.
        for (compile.getCompileDependencies(true)) |some_compile| {
            for (some_compile.root_module.getGraph().modules) |mod| {
                if (mod.link_libc == true) compile.is_linking_libc = true;
                if (mod.link_libcpp == true) compile.is_linking_libcpp = true;
            }
        }

        var cli_named_modules = try CliNamedModules.init(arena, compile.root_module);

        // For this loop, don't chase dynamic libraries because their link
        // objects are already linked.
        for (compile.getCompileDependencies(false)) |dep_compile| {
            for (dep_compile.root_module.getGraph().modules) |mod| {
                // While walking transitive dependencies, if a given link object is
                // already included in a library, it should not redundantly be
                // placed on the linker line of the dependee.
                const my_responsibility = dep_compile == compile;
                const already_linked = !my_responsibility and dep_compile.isDynamicLibrary();

                // Inherit dependencies on darwin frameworks.
                if (!already_linked) {
                    for (mod.frameworks.keys(), mod.frameworks.values()) |name, info| {
                        try frameworks.put(arena, name, info);
                    }
                }

                // Inherit dependencies on system libraries and static libraries.
                for (mod.link_objects.items) |link_object| {
                    switch (link_object) {
                        .static_path => |static_path| {
                            if (my_responsibility) {
                                try zig_args.append(static_path.getPath2(mod.owner, step));
                                total_linker_objects += 1;
                            }
                        },
                        .system_lib => |system_lib| {
                            const system_lib_gop = try seen_system_libs.getOrPut(arena, system_lib.name);
                            if (system_lib_gop.found_existing) {
                                try zig_args.appendSlice(system_lib_gop.value_ptr.*);
                                continue;
                            } else {
                                system_lib_gop.value_ptr.* = &.{};
                            }

                            if (already_linked)
                                continue;

                            if ((system_lib.search_strategy != prev_search_strategy or
                                system_lib.preferred_link_mode != prev_preferred_link_mode) and
                                compile.linkage != .static)
                            {
                                switch (system_lib.search_strategy) {
                                    .no_fallback => switch (system_lib.preferred_link_mode) {
                                        .dynamic => try zig_args.append("-search_dylibs_only"),
                                        .static => try zig_args.append("-search_static_only"),
                                    },
                                    .paths_first => switch (system_lib.preferred_link_mode) {
                                        .dynamic => try zig_args.append("-search_paths_first"),
                                        .static => try zig_args.append("-search_paths_first_static"),
                                    },
                                    .mode_first => switch (system_lib.preferred_link_mode) {
                                        .dynamic => try zig_args.append("-search_dylibs_first"),
                                        .static => try zig_args.append("-search_static_first"),
                                    },
                                }
                                prev_search_strategy = system_lib.search_strategy;
                                prev_preferred_link_mode = system_lib.preferred_link_mode;
                            }

                            const prefix: []const u8 = prefix: {
                                if (system_lib.needed) break :prefix "-needed-l";
                                if (system_lib.weak) break :prefix "-weak-l";
                                break :prefix "-l";
                            };
                            switch (system_lib.use_pkg_config) {
                                .no => try zig_args.append(b.fmt("{s}{s}", .{ prefix, system_lib.name })),
                                .yes, .force => {
                                    if (compile.runPkgConfig(system_lib.name)) |result| {
                                        try zig_args.appendSlice(result.cflags);
                                        try zig_args.appendSlice(result.libs);
                                        try seen_system_libs.put(arena, system_lib.name, result.cflags);
                                    } else |err| switch (err) {
                                        error.PkgConfigInvalidOutput,
                                        error.PkgConfigCrashed,
                                        error.PkgConfigFailed,
                                        error.PkgConfigNotInstalled,
                                        error.PackageNotFound,
                                        => switch (system_lib.use_pkg_config) {
                                            .yes => {
                                                // pkg-config failed, so fall back to linking the library
                                                // by name directly.
                                                try zig_args.append(b.fmt("{s}{s}", .{
                                                    prefix,
                                                    system_lib.name,
                                                }));
                                            },
                                            .force => {
                                                panic("pkg-config failed for library {s}", .{system_lib.name});
                                            },
                                            .no => unreachable,
                                        },

                                        else => |e| return e,
                                    }
                                },
                            }
                        },
                        .other_step => |other| {
                            switch (other.kind) {
                                .exe => return step.fail("cannot link with an executable build artifact", .{}),
                                .@"test" => return step.fail("cannot link with a test", .{}),
                                .obj, .test_obj => {
                                    const included_in_lib_or_obj = !my_responsibility and
                                        (dep_compile.kind == .lib or dep_compile.kind == .obj or dep_compile.kind == .test_obj);
                                    if (!already_linked and !included_in_lib_or_obj) {
                                        try zig_args.append(other.getEmittedBin().getPath2(b, step));
                                        total_linker_objects += 1;
                                    }
                                },
                                .lib => l: {
                                    const other_produces_implib = other.producesImplib();
                                    const other_is_static = other_produces_implib or other.isStaticLibrary();

                                    if (compile.isStaticLibrary() and other_is_static) {
                                        // Avoid putting a static library inside a static library.
                                        break :l;
                                    }

                                    // For DLLs, we must link against the implib.
                                    // For everything else, we directly link
                                    // against the library file.
                                    const full_path_lib = if (other_produces_implib)
                                        other.getGeneratedFilePath("generated_implib", &compile.step)
                                    else
                                        other.getGeneratedFilePath("generated_bin", &compile.step);

                                    try zig_args.append(full_path_lib);
                                    total_linker_objects += 1;

                                    if (other.linkage == .dynamic and
                                        compile.rootModuleTarget().os.tag != .windows)
                                    {
                                        if (fs.path.dirname(full_path_lib)) |dirname| {
                                            try zig_args.append("-rpath");
                                            try zig_args.append(dirname);
                                        }
                                    }
                                },
                            }
                        },
                        .assembly_file => |asm_file| l: {
                            if (!my_responsibility) break :l;

                            if (prev_has_cflags) {
                                try zig_args.append("-cflags");
                                try zig_args.append("--");
                                prev_has_cflags = false;
                            }
                            try zig_args.append(asm_file.getPath2(mod.owner, step));
                            total_linker_objects += 1;
                        },

                        .c_source_file => |c_source_file| l: {
                            if (!my_responsibility) break :l;

                            if (prev_has_cflags or c_source_file.flags.len != 0) {
                                try zig_args.append("-cflags");
                                for (c_source_file.flags) |arg| {
                                    try zig_args.append(arg);
                                }
                                try zig_args.append("--");
                            }
                            prev_has_cflags = (c_source_file.flags.len != 0);

                            if (c_source_file.language) |lang| {
                                try zig_args.append("-x");
                                try zig_args.append(lang.internalIdentifier());
                            }

                            try zig_args.append(c_source_file.file.getPath2(mod.owner, step));

                            if (c_source_file.language != null) {
                                try zig_args.append("-x");
                                try zig_args.append("none");
                            }
                            total_linker_objects += 1;
                        },

                        .c_source_files => |c_source_files| l: {
                            if (!my_responsibility) break :l;

                            if (prev_has_cflags or c_source_files.flags.len != 0) {
                                try zig_args.append("-cflags");
                                for (c_source_files.flags) |arg| {
                                    try zig_args.append(arg);
                                }
                                try zig_args.append("--");
                            }
                            prev_has_cflags = (c_source_files.flags.len != 0);

                            if (c_source_files.language) |lang| {
                                try zig_args.append("-x");
                                try zig_args.append(lang.internalIdentifier());
                            }

                            const root_path = c_source_files.root.getPath2(mod.owner, step);
                            for (c_source_files.files) |file| {
                                try zig_args.append(b.pathJoin(&.{ root_path, file }));
                            }

                            if (c_source_files.language != null) {
                                try zig_args.append("-x");
                                try zig_args.append("none");
                            }

                            total_linker_objects += c_source_files.files.len;
                        },

                        .win32_resource_file => |rc_source_file| l: {
                            if (!my_responsibility) break :l;

                            if (rc_source_file.flags.len == 0 and rc_source_file.include_paths.len == 0) {
                                if (prev_has_rcflags) {
                                    try zig_args.append("-rcflags");
                                    try zig_args.append("--");
                                    prev_has_rcflags = false;
                                }
                            } else {
                                try zig_args.append("-rcflags");
                                for (rc_source_file.flags) |arg| {
                                    try zig_args.append(arg);
                                }
                                for (rc_source_file.include_paths) |include_path| {
                                    try zig_args.append("/I");
                                    try zig_args.append(include_path.getPath2(mod.owner, step));
                                }
                                try zig_args.append("--");
                                prev_has_rcflags = true;
                            }
                            try zig_args.append(rc_source_file.file.getPath2(mod.owner, step));
                            total_linker_objects += 1;
                        },
                    }
                }

                // We need to emit the --mod argument here so that the above link objects
                // have the correct parent module, but only if the module is part of
                // this compilation.
                if (!my_responsibility) continue;
                if (cli_named_modules.modules.getIndex(mod)) |module_cli_index| {
                    const module_cli_name = cli_named_modules.names.keys()[module_cli_index];
                    try mod.appendZigProcessFlags(&zig_args, step);

                    // --dep arguments
                    try zig_args.ensureUnusedCapacity(mod.import_table.count() * 2);
                    for (mod.import_table.keys(), mod.import_table.values()) |name, import| {
                        const import_index = cli_named_modules.modules.getIndex(import).?;
                        const import_cli_name = cli_named_modules.names.keys()[import_index];
                        zig_args.appendAssumeCapacity("--dep");
                        if (std.mem.eql(u8, import_cli_name, name)) {
                            zig_args.appendAssumeCapacity(import_cli_name);
                        } else {
                            zig_args.appendAssumeCapacity(b.fmt("{s}={s}", .{ name, import_cli_name }));
                        }
                    }

                    // When the CLI sees a -M argument, it determines whether it
                    // implies the existence of a Zig compilation unit based on
                    // whether there is a root source file. If there is no root
                    // source file, then this is not a zig compilation unit - it is
                    // perhaps a set of linker objects, or C source files instead.
                    // Linker objects are added to the CLI globally, while C source
                    // files must have a module parent.
                    if (mod.root_source_file) |lp| {
                        const src = lp.getPath2(mod.owner, step);
                        try zig_args.append(b.fmt("-M{s}={s}", .{ module_cli_name, src }));
                    } else if (moduleNeedsCliArg(mod)) {
                        try zig_args.append(b.fmt("-M{s}", .{module_cli_name}));
                    }
                }
            }
        }

        if (total_linker_objects == 0) {
            return step.fail("the linker needs one or more objects to link", .{});
        }

        for (frameworks.keys(), frameworks.values()) |name, info| {
            if (info.needed) {
                try zig_args.append("-needed_framework");
            } else if (info.weak) {
                try zig_args.append("-weak_framework");
            } else {
                try zig_args.append("-framework");
            }
            try zig_args.append(name);
        }

        if (compile.is_linking_libcpp) {
            try zig_args.append("-lc++");
        }

        if (compile.is_linking_libc) {
            try zig_args.append("-lc");
        }
    }

    if (compile.win32_manifest) |manifest_file| {
        try zig_args.append(manifest_file.getPath2(b, step));
    }

    if (compile.image_base) |image_base| {
        try zig_args.append("--image-base");
        try zig_args.append(b.fmt("0x{x}", .{image_base}));
    }

    for (compile.filters) |filter| {
        try zig_args.append("--test-filter");
        try zig_args.append(filter);
    }

    if (compile.test_runner) |test_runner| {
        try zig_args.append("--test-runner");
        try zig_args.append(test_runner.path.getPath2(b, step));
    }

    for (b.debug_log_scopes) |log_scope| {
        try zig_args.append("--debug-log");
        try zig_args.append(log_scope);
    }

    if (b.debug_compile_errors) {
        try zig_args.append("--debug-compile-errors");
    }

    if (b.debug_incremental) {
        try zig_args.append("--debug-incremental");
    }

    if (b.verbose_cimport) try zig_args.append("--verbose-cimport");
    if (b.verbose_air) try zig_args.append("--verbose-air");
    if (b.verbose_llvm_ir) |path| try zig_args.append(b.fmt("--verbose-llvm-ir={s}", .{path}));
    if (b.verbose_llvm_bc) |path| try zig_args.append(b.fmt("--verbose-llvm-bc={s}", .{path}));
    if (b.verbose_link or compile.verbose_link) try zig_args.append("--verbose-link");
    if (b.verbose_cc or compile.verbose_cc) try zig_args.append("--verbose-cc");
    if (b.verbose_llvm_cpu_features) try zig_args.append("--verbose-llvm-cpu-features");

    if (compile.generated_asm != null) try zig_args.append("-femit-asm");
    if (compile.generated_bin == null) try zig_args.append("-fno-emit-bin");
    if (compile.generated_docs != null) try zig_args.append("-femit-docs");
    if (compile.generated_implib != null) try zig_args.append("-femit-implib");
    if (compile.generated_llvm_bc != null) try zig_args.append("-femit-llvm-bc");
    if (compile.generated_llvm_ir != null) try zig_args.append("-femit-llvm-ir");
    if (compile.generated_h != null) try zig_args.append("-femit-h");

    try addFlag(&zig_args, "formatted-panics", compile.formatted_panics);

    switch (compile.compress_debug_sections) {
        .none => {},
        .zlib => try zig_args.append("--compress-debug-sections=zlib"),
        .zstd => try zig_args.append("--compress-debug-sections=zstd"),
    }

    if (compile.link_eh_frame_hdr) {
        try zig_args.append("--eh-frame-hdr");
    }
    if (compile.link_emit_relocs) {
        try zig_args.append("--emit-relocs");
    }
    if (compile.link_function_sections) {
        try zig_args.append("-ffunction-sections");
    }
    if (compile.link_data_sections) {
        try zig_args.append("-fdata-sections");
    }
    if (compile.link_gc_sections) |x| {
        try zig_args.append(if (x) "--gc-sections" else "--no-gc-sections");
    }
    if (!compile.linker_dynamicbase) {
        try zig_args.append("--no-dynamicbase");
    }
    if (compile.linker_allow_shlib_undefined) |x| {
        try zig_args.append(if (x) "-fallow-shlib-undefined" else "-fno-allow-shlib-undefined");
    }
    if (compile.link_z_notext) {
        try zig_args.append("-z");
        try zig_args.append("notext");
    }
    if (!compile.link_z_relro) {
        try zig_args.append("-z");
        try zig_args.append("norelro");
    }
    if (compile.link_z_lazy) {
        try zig_args.append("-z");
        try zig_args.append("lazy");
    }
    if (compile.link_z_common_page_size) |size| {
        try zig_args.append("-z");
        try zig_args.append(b.fmt("common-page-size={d}", .{size}));
    }
    if (compile.link_z_max_page_size) |size| {
        try zig_args.append("-z");
        try zig_args.append(b.fmt("max-page-size={d}", .{size}));
    }

    if (compile.libc_file) |libc_file| {
        try zig_args.append("--libc");
        try zig_args.append(libc_file.getPath2(b, step));
    } else if (b.libc_file) |libc_file| {
        try zig_args.append("--libc");
        try zig_args.append(libc_file);
    }

    try zig_args.append("--cache-dir");
    try zig_args.append(b.cache_root.path orelse ".");

    try zig_args.append("--global-cache-dir");
    try zig_args.append(b.graph.global_cache_root.path orelse ".");

    if (b.graph.debug_compiler_runtime_libs) try zig_args.append("--debug-rt");

    try zig_args.append("--name");
    try zig_args.append(compile.name);

    if (compile.linkage) |some| switch (some) {
        .dynamic => try zig_args.append("-dynamic"),
        .static => try zig_args.append("-static"),
    };
    if (compile.kind == .lib and compile.linkage != null and compile.linkage.? == .dynamic) {
        if (compile.version) |version| {
            try zig_args.append("--version");
            try zig_args.append(b.fmt("{f}", .{version}));
        }

        if (compile.rootModuleTarget().os.tag.isDarwin()) {
            const install_name = compile.install_name orelse b.fmt("@rpath/{s}{s}{s}", .{
                compile.rootModuleTarget().libPrefix(),
                compile.name,
                compile.rootModuleTarget().dynamicLibSuffix(),
            });
            try zig_args.append("-install_name");
            try zig_args.append(install_name);
        }
    }

    if (compile.entitlements) |entitlements| {
        try zig_args.appendSlice(&[_][]const u8{ "--entitlements", entitlements });
    }
    if (compile.pagezero_size) |pagezero_size| {
        const size = try std.fmt.allocPrint(arena, "{x}", .{pagezero_size});
        try zig_args.appendSlice(&[_][]const u8{ "-pagezero_size", size });
    }
    if (compile.headerpad_size) |headerpad_size| {
        const size = try std.fmt.allocPrint(arena, "{x}", .{headerpad_size});
        try zig_args.appendSlice(&[_][]const u8{ "-headerpad", size });
    }
    if (compile.headerpad_max_install_names) {
        try zig_args.append("-headerpad_max_install_names");
    }
    if (compile.dead_strip_dylibs) {
        try zig_args.append("-dead_strip_dylibs");
    }
    if (compile.force_load_objc) {
        try zig_args.append("-ObjC");
    }
    if (compile.discard_local_symbols) {
        try zig_args.append("--discard-all");
    }

    try addFlag(&zig_args, "compiler-rt", compile.bundle_compiler_rt);
    try addFlag(&zig_args, "ubsan-rt", compile.bundle_ubsan_rt);
    try addFlag(&zig_args, "dll-export-fns", compile.dll_export_fns);
    if (compile.rdynamic) {
        try zig_args.append("-rdynamic");
    }
    if (compile.import_memory) {
        try zig_args.append("--import-memory");
    }
    if (compile.export_memory) {
        try zig_args.append("--export-memory");
    }
    if (compile.import_symbols) {
        try zig_args.append("--import-symbols");
    }
    if (compile.import_table) {
        try zig_args.append("--import-table");
    }
    if (compile.export_table) {
        try zig_args.append("--export-table");
    }
    if (compile.initial_memory) |initial_memory| {
        try zig_args.append(b.fmt("--initial-memory={d}", .{initial_memory}));
    }
    if (compile.max_memory) |max_memory| {
        try zig_args.append(b.fmt("--max-memory={d}", .{max_memory}));
    }
    if (compile.shared_memory) {
        try zig_args.append("--shared-memory");
    }
    if (compile.global_base) |global_base| {
        try zig_args.append(b.fmt("--global-base={d}", .{global_base}));
    }

    if (compile.wasi_exec_model) |model| {
        try zig_args.append(b.fmt("-mexec-model={s}", .{@tagName(model)}));
    }
    if (compile.linker_script) |linker_script| {
        try zig_args.append("--script");
        try zig_args.append(linker_script.getPath2(b, step));
    }

    if (compile.version_script) |version_script| {
        try zig_args.append("--version-script");
        try zig_args.append(version_script.getPath2(b, step));
    }
    if (compile.linker_allow_undefined_version) |x| {
        try zig_args.append(if (x) "--undefined-version" else "--no-undefined-version");
    }

    if (compile.linker_enable_new_dtags) |enabled| {
        try zig_args.append(if (enabled) "--enable-new-dtags" else "--disable-new-dtags");
    }

    if (compile.kind == .@"test") {
        if (compile.exec_cmd_args) |exec_cmd_args| {
            for (exec_cmd_args) |cmd_arg| {
                if (cmd_arg) |arg| {
                    try zig_args.append("--test-cmd");
                    try zig_args.append(arg);
                } else {
                    try zig_args.append("--test-cmd-bin");
                }
            }
        }
    }

    if (b.sysroot) |sysroot| {
        try zig_args.appendSlice(&[_][]const u8{ "--sysroot", sysroot });
    }

    // -I and -L arguments that appear after the last --mod argument apply to all modules.
    for (b.search_prefixes.items) |search_prefix| {
        var prefix_dir = fs.cwd().openDir(search_prefix, .{}) catch |err| {
            return step.fail("unable to open prefix directory '{s}': {s}", .{
                search_prefix, @errorName(err),
            });
        };
        defer prefix_dir.close();

        // Avoid passing -L and -I flags for nonexistent directories.
        // This prevents a warning, that should probably be upgraded to an error in Zig's
        // CLI parsing code, when the linker sees an -L directory that does not exist.

        if (prefix_dir.accessZ("lib", .{})) |_| {
            try zig_args.appendSlice(&.{
                "-L", b.pathJoin(&.{ search_prefix, "lib" }),
            });
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => |e| return step.fail("unable to access '{s}/lib' directory: {s}", .{
                search_prefix, @errorName(e),
            }),
        }

        if (prefix_dir.accessZ("include", .{})) |_| {
            try zig_args.appendSlice(&.{
                "-I", b.pathJoin(&.{ search_prefix, "include" }),
            });
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => |e| return step.fail("unable to access '{s}/include' directory: {s}", .{
                search_prefix, @errorName(e),
            }),
        }
    }

    if (compile.rc_includes != .any) {
        try zig_args.append("-rcincludes");
        try zig_args.append(@tagName(compile.rc_includes));
    }

    try addFlag(&zig_args, "each-lib-rpath", compile.each_lib_rpath);

    if (compile.build_id orelse b.build_id) |build_id| {
        try zig_args.append(switch (build_id) {
            .hexstring => |hs| b.fmt("--build-id=0x{x}", .{hs.toSlice()}),
            .none, .fast, .uuid, .sha1, .md5 => b.fmt("--build-id={s}", .{@tagName(build_id)}),
        });
    }

    const opt_zig_lib_dir = if (compile.zig_lib_dir) |dir|
        dir.getPath2(b, step)
    else if (b.graph.zig_lib_directory.path) |_|
        b.fmt("{f}", .{b.graph.zig_lib_directory})
    else
        null;

    if (opt_zig_lib_dir) |zig_lib_dir| {
        try zig_args.append("--zig-lib-dir");
        try zig_args.append(zig_lib_dir);
    }

    try addFlag(&zig_args, "PIE", compile.pie);

    if (compile.lto) |lto| {
        try zig_args.append(switch (lto) {
            .full => "-flto=full",
            .thin => "-flto=thin",
            .none => "-fno-lto",
        });
    } else try addFlag(&zig_args, "lto", compile.want_lto);

    try addFlag(&zig_args, "sanitize-coverage-trace-pc-guard", compile.sanitize_coverage_trace_pc_guard);

    if (compile.subsystem) |subsystem| {
        try zig_args.append("--subsystem");
        try zig_args.append(switch (subsystem) {
            .Console => "console",
            .Windows => "windows",
            .Posix => "posix",
            .Native => "native",
            .EfiApplication => "efi_application",
            .EfiBootServiceDriver => "efi_boot_service_driver",
            .EfiRom => "efi_rom",
            .EfiRuntimeDriver => "efi_runtime_driver",
        });
    }

    if (compile.mingw_unicode_entry_point) {
        try zig_args.append("-municode");
    }

    if (compile.error_limit) |err_limit| try zig_args.appendSlice(&.{
        "--error-limit", b.fmt("{d}", .{err_limit}),
    });

    try addFlag(&zig_args, "incremental", b.graph.incremental);

    try zig_args.append("--listen=-");

    // Windows has an argument length limit of 32,766 characters, macOS 262,144 and Linux
    // 2,097,152. If our args exceed 30 KiB, we instead write them to a "response file" and
    // pass that to zig, e.g. via 'zig build-lib @args.rsp'
    // See @file syntax here: https://gcc.gnu.org/onlinedocs/gcc/Overall-Options.html
    var args_length: usize = 0;
    for (zig_args.items) |arg| {
        args_length += arg.len + 1; // +1 to account for null terminator
    }
    if (args_length >= 30 * 1024) {
        try b.cache_root.handle.makePath("args");

        const args_to_escape = zig_args.items[2..];
        var escaped_args = try ArrayList([]const u8).initCapacity(arena, args_to_escape.len);
        arg_blk: for (args_to_escape) |arg| {
            for (arg, 0..) |c, arg_idx| {
                if (c == '\\' or c == '"') {
                    // Slow path for arguments that need to be escaped. We'll need to allocate and copy
                    var escaped: std.ArrayListUnmanaged(u8) = .empty;
                    try escaped.ensureTotalCapacityPrecise(arena, arg.len + 1);
                    try escaped.appendSlice(arena, arg[0..arg_idx]);
                    for (arg[arg_idx..]) |to_escape| {
                        if (to_escape == '\\' or to_escape == '"') try escaped.append(arena, '\\');
                        try escaped.append(arena, to_escape);
                    }
                    escaped_args.appendAssumeCapacity(escaped.items);
                    continue :arg_blk;
                }
            }
            escaped_args.appendAssumeCapacity(arg); // no escaping needed so just use original argument
        }

        // Write the args to zig-cache/args/<SHA256 hash of args> to avoid conflicts with
        // other zig build commands running in parallel.
        const partially_quoted = try std.mem.join(arena, "\" \"", escaped_args.items);
        const args = try std.mem.concat(arena, u8, &[_][]const u8{ "\"", partially_quoted, "\"" });

        var args_hash: [Sha256.digest_length]u8 = undefined;
        Sha256.hash(args, &args_hash, .{});
        var args_hex_hash: [Sha256.digest_length * 2]u8 = undefined;
        _ = try std.fmt.bufPrint(&args_hex_hash, "{x}", .{&args_hash});

        const args_file = "args" ++ fs.path.sep_str ++ args_hex_hash;
        try b.cache_root.handle.writeFile(.{ .sub_path = args_file, .data = args });

        const resolved_args_file = try mem.concat(arena, u8, &.{
            "@",
            try b.cache_root.join(arena, &.{args_file}),
        });

        zig_args.shrinkRetainingCapacity(2);
        try zig_args.append(resolved_args_file);
    }

    return try zig_args.toOwnedSlice();
}

fn make(step: *Step, options: Step.MakeOptions) !void {
    const b = step.owner;
    const compile: *Compile = @fieldParentPtr("step", step);

    const zig_args = try getZigArgs(compile, false);

    const maybe_output_dir = step.evalZigProcess(
        zig_args,
        options.progress_node,
        (b.graph.incremental == true) and options.watch,
    ) catch |err| switch (err) {
        error.NeedCompileErrorCheck => {
            assert(compile.expect_errors != null);
            try checkCompileErrors(compile);
            return;
        },
        else => |e| return e,
    };

    // Update generated files
    if (maybe_output_dir) |output_dir| {
        if (compile.emit_directory) |lp| {
            lp.path = b.fmt("{f}", .{output_dir});
        }

        // zig fmt: off
        if (compile.generated_bin)     |lp| lp.path = compile.outputPath(output_dir, .bin);
        if (compile.generated_pdb)     |lp| lp.path = compile.outputPath(output_dir, .pdb);
        if (compile.generated_implib)  |lp| lp.path = compile.outputPath(output_dir, .implib);
        if (compile.generated_h)       |lp| lp.path = compile.outputPath(output_dir, .h);
        if (compile.generated_docs)    |lp| lp.path = compile.outputPath(output_dir, .docs);
        if (compile.generated_asm)     |lp| lp.path = compile.outputPath(output_dir, .@"asm");
        if (compile.generated_llvm_ir) |lp| lp.path = compile.outputPath(output_dir, .llvm_ir);
        if (compile.generated_llvm_bc) |lp| lp.path = compile.outputPath(output_dir, .llvm_bc);
        // zig fmt: on
    }

    if (compile.kind == .lib and compile.linkage != null and compile.linkage.? == .dynamic and
        compile.version != null and std.Build.wantSharedLibSymLinks(compile.rootModuleTarget()))
    {
        try doAtomicSymLinks(
            step,
            compile.getEmittedBin().getPath2(b, step),
            compile.major_only_filename.?,
            compile.name_only_filename.?,
        );
    }
}
fn outputPath(c: *Compile, out_dir: std.Build.Cache.Path, ea: std.zig.EmitArtifact) []const u8 {
    const arena = c.step.owner.graph.arena;
    const name = ea.cacheName(arena, .{
        .root_name = c.name,
        .target = &c.root_module.resolved_target.?.result,
        .output_mode = switch (c.kind) {
            .lib => .Lib,
            .obj, .test_obj => .Obj,
            .exe, .@"test" => .Exe,
        },
        .link_mode = c.linkage,
        .version = c.version,
    }) catch @panic("OOM");
    return out_dir.joinString(arena, name) catch @panic("OOM");
}

pub fn rebuildInFuzzMode(c: *Compile, progress_node: std.Progress.Node) !Path {
    const gpa = c.step.owner.allocator;

    c.step.result_error_msgs.clearRetainingCapacity();
    c.step.result_stderr = "";

    c.step.result_error_bundle.deinit(gpa);
    c.step.result_error_bundle = std.zig.ErrorBundle.empty;

    const zig_args = try getZigArgs(c, true);
    const maybe_output_bin_path = try c.step.evalZigProcess(zig_args, progress_node, false);
    return maybe_output_bin_path.?;
}

pub fn doAtomicSymLinks(
    step: *Step,
    output_path: []const u8,
    filename_major_only: []const u8,
    filename_name_only: []const u8,
) !void {
    const b = step.owner;
    const out_dir = fs.path.dirname(output_path) orelse ".";
    const out_basename = fs.path.basename(output_path);
    // sym link for libfoo.so.1 to libfoo.so.1.2.3
    const major_only_path = b.pathJoin(&.{ out_dir, filename_major_only });
    fs.cwd().atomicSymLink(out_basename, major_only_path, .{}) catch |err| {
        return step.fail("unable to symlink {s} -> {s}: {s}", .{
            major_only_path, out_basename, @errorName(err),
        });
    };
    // sym link for libfoo.so to libfoo.so.1
    const name_only_path = b.pathJoin(&.{ out_dir, filename_name_only });
    fs.cwd().atomicSymLink(filename_major_only, name_only_path, .{}) catch |err| {
        return step.fail("Unable to symlink {s} -> {s}: {s}", .{
            name_only_path, filename_major_only, @errorName(err),
        });
    };
}

fn execPkgConfigList(b: *std.Build, out_code: *u8) (PkgConfigError || RunError)![]const PkgConfigPkg {
    const pkg_config_exe = b.graph.env_map.get("PKG_CONFIG") orelse "pkg-config";
    const stdout = try b.runAllowFail(&[_][]const u8{ pkg_config_exe, "--list-all" }, out_code, .Ignore);
    var list = ArrayList(PkgConfigPkg).init(b.allocator);
    errdefer list.deinit();
    var line_it = mem.tokenizeAny(u8, stdout, "\r\n");
    while (line_it.next()) |line| {
        if (mem.trim(u8, line, " \t").len == 0) continue;
        var tok_it = mem.tokenizeAny(u8, line, " \t");
        try list.append(PkgConfigPkg{
            .name = tok_it.next() orelse return error.PkgConfigInvalidOutput,
            .desc = tok_it.rest(),
        });
    }
    return list.toOwnedSlice();
}

fn getPkgConfigList(b: *std.Build) ![]const PkgConfigPkg {
    if (b.pkg_config_pkg_list) |res| {
        return res;
    }
    var code: u8 = undefined;
    if (execPkgConfigList(b, &code)) |list| {
        b.pkg_config_pkg_list = list;
        return list;
    } else |err| {
        const result = switch (err) {
            error.ProcessTerminated => error.PkgConfigCrashed,
            error.ExecNotSupported => error.PkgConfigFailed,
            error.ExitCodeFailure => error.PkgConfigFailed,
            error.FileNotFound => error.PkgConfigNotInstalled,
            error.InvalidName => error.PkgConfigNotInstalled,
            error.PkgConfigInvalidOutput => error.PkgConfigInvalidOutput,
            else => return err,
        };
        b.pkg_config_pkg_list = result;
        return result;
    }
}

fn addFlag(args: *ArrayList([]const u8), comptime name: []const u8, opt: ?bool) !void {
    const cond = opt orelse return;
    try args.ensureUnusedCapacity(1);
    if (cond) {
        args.appendAssumeCapacity("-f" ++ name);
    } else {
        args.appendAssumeCapacity("-fno-" ++ name);
    }
}

fn checkCompileErrors(compile: *Compile) !void {
    // Clear this field so that it does not get printed by the build runner.
    const actual_eb = compile.step.result_error_bundle;
    compile.step.result_error_bundle = .empty;

    const arena = compile.step.owner.allocator;

    const actual_errors = ae: {
        var aw: std.io.Writer.Allocating = .init(arena);
        defer aw.deinit();
        try actual_eb.renderToWriter(.{
            .ttyconf = .no_color,
            .include_reference_trace = false,
            .include_source_line = false,
        }, &aw.writer);
        break :ae try aw.toOwnedSlice();
    };

    // Render the expected lines into a string that we can compare verbatim.
    var expected_generated: std.ArrayListUnmanaged(u8) = .empty;
    const expect_errors = compile.expect_errors.?;

    var actual_line_it = mem.splitScalar(u8, actual_errors, '\n');

    // TODO merge this with the testing.expectEqualStrings logic, and also CheckFile
    switch (expect_errors) {
        .starts_with => |expect_starts_with| {
            if (std.mem.startsWith(u8, actual_errors, expect_starts_with)) return;
            return compile.step.fail(
                \\
                \\========= should start with: ============
                \\{s}
                \\========= but not found: ================
                \\{s}
                \\=========================================
            , .{ expect_starts_with, actual_errors });
        },
        .contains => |expect_line| {
            while (actual_line_it.next()) |actual_line| {
                if (!matchCompileError(actual_line, expect_line)) continue;
                return;
            }

            return compile.step.fail(
                \\
                \\========= should contain: ===============
                \\{s}
                \\========= but not found: ================
                \\{s}
                \\=========================================
            , .{ expect_line, actual_errors });
        },
        .stderr_contains => |expect_line| {
            const actual_stderr: []const u8 = if (compile.step.result_error_msgs.items.len > 0)
                compile.step.result_error_msgs.items[0]
            else
                &.{};
            compile.step.result_error_msgs.clearRetainingCapacity();

            var stderr_line_it = mem.splitScalar(u8, actual_stderr, '\n');

            while (stderr_line_it.next()) |actual_line| {
                if (!matchCompileError(actual_line, expect_line)) continue;
                return;
            }

            return compile.step.fail(
                \\
                \\========= should contain: ===============
                \\{s}
                \\========= but not found: ================
                \\{s}
                \\=========================================
            , .{ expect_line, actual_stderr });
        },
        .exact => |expect_lines| {
            for (expect_lines) |expect_line| {
                const actual_line = actual_line_it.next() orelse {
                    try expected_generated.appendSlice(arena, expect_line);
                    try expected_generated.append(arena, '\n');
                    continue;
                };
                if (matchCompileError(actual_line, expect_line)) {
                    try expected_generated.appendSlice(arena, actual_line);
                    try expected_generated.append(arena, '\n');
                    continue;
                }
                try expected_generated.appendSlice(arena, expect_line);
                try expected_generated.append(arena, '\n');
            }

            if (mem.eql(u8, expected_generated.items, actual_errors)) return;

            return compile.step.fail(
                \\
                \\========= expected: =====================
                \\{s}
                \\========= but found: ====================
                \\{s}
                \\=========================================
            , .{ expected_generated.items, actual_errors });
        },
    }
}

fn matchCompileError(actual: []const u8, expected: []const u8) bool {
    if (mem.endsWith(u8, actual, expected)) return true;
    if (mem.startsWith(u8, expected, ":?:?: ")) {
        if (mem.endsWith(u8, actual, expected[":?:?: ".len..])) return true;
    }
    // We scan for /?/ in expected line and if there is a match, we match everything
    // up to and after /?/.
    const expected_trim = mem.trim(u8, expected, " ");
    if (mem.indexOf(u8, expected_trim, "/?/")) |index| {
        const actual_trim = mem.trim(u8, actual, " ");
        const lhs = expected_trim[0..index];
        const rhs = expected_trim[index + "/?/".len ..];
        if (mem.startsWith(u8, actual_trim, lhs) and mem.endsWith(u8, actual_trim, rhs)) return true;
    }
    return false;
}

pub fn rootModuleTarget(c: *Compile) std.Target {
    // The root module is always given a target, so we know this to be non-null.
    return c.root_module.resolved_target.?.result;
}

fn moduleNeedsCliArg(mod: *const Module) bool {
    return for (mod.link_objects.items) |o| switch (o) {
        .c_source_file, .c_source_files, .assembly_file, .win32_resource_file => break true,
        else => continue,
    } else false;
}

/// Return the full set of `Step.Compile` which `start` depends on, recursively. `start` itself is
/// always returned as the first element. If `chase_dynamic` is `false`, then dynamic libraries are
/// not included, and their dependencies are not considered; if `chase_dynamic` is `true`, dynamic
/// libraries are treated the same as other linked `Compile`s.
pub fn getCompileDependencies(start: *Compile, chase_dynamic: bool) []const *Compile {
    const arena = start.step.owner.graph.arena;

    var compiles: std.AutoArrayHashMapUnmanaged(*Compile, void) = .empty;
    var next_idx: usize = 0;

    compiles.putNoClobber(arena, start, {}) catch @panic("OOM");

    while (next_idx < compiles.count()) {
        const compile = compiles.keys()[next_idx];
        next_idx += 1;

        for (compile.root_module.getGraph().modules) |mod| {
            for (mod.link_objects.items) |lo| {
                switch (lo) {
                    .other_step => |other_compile| {
                        if (!chase_dynamic and other_compile.isDynamicLibrary()) continue;
                        compiles.put(arena, other_compile, {}) catch @panic("OOM");
                    },
                    else => {},
                }
            }
        }
    }

    return compiles.keys();
}
