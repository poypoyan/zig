const std = @import("std");
const builtin = @import("builtin");
const Target = std.Target;

/// Only covers EAX for now.
const Xcr0 = packed struct(u32) {
    x87: bool,
    sse: bool,
    avx: bool,
    bndreg: bool,
    bndcsr: bool,
    opmask: bool,
    zmm_hi256: bool,
    hi16_zmm: bool,
    pt: bool,
    pkru: bool,
    pasid: bool,
    cet_u: bool,
    cet_s: bool,
    hdc: bool,
    uintr: bool,
    lbr: bool,
    hwp: bool,
    xtilecfg: bool,
    xtiledata: bool,
    apx: bool,
    _reserved: u12,
};

fn setFeature(cpu: *Target.Cpu, feature: Target.x86.Feature, enabled: bool) void {
    const idx = @as(Target.Cpu.Feature.Set.Index, @intFromEnum(feature));

    if (enabled) cpu.features.addFeature(idx) else cpu.features.removeFeature(idx);
}

inline fn bit(input: u32, offset: u5) bool {
    return (input >> offset) & 1 != 0;
}

inline fn hasMask(input: u32, mask: u32) bool {
    return (input & mask) == mask;
}

pub fn detectNativeCpuAndFeatures(arch: Target.Cpu.Arch, os: Target.Os, query: Target.Query) Target.Cpu {
    _ = query;
    var cpu = Target.Cpu{
        .arch = arch,
        .model = Target.Cpu.Model.generic(arch),
        .features = Target.Cpu.Feature.Set.empty,
    };

    // First we detect features, to use as hints when detecting CPU Model.
    detectNativeFeatures(&cpu, os.tag);

    var leaf = cpuid(0, 0);
    const max_leaf = leaf.eax;
    const vendor = leaf.ebx;

    if (max_leaf > 0) {
        leaf = cpuid(0x1, 0);

        const brand_id = leaf.ebx & 0xff;

        // Detect model and family
        var family = (leaf.eax >> 8) & 0xf;
        var model = (leaf.eax >> 4) & 0xf;
        if (family == 6 or family == 0xf) {
            if (family == 0xf) {
                family += (leaf.eax >> 20) & 0xff;
            }
            model += ((leaf.eax >> 16) & 0xf) << 4;
        }

        // Now we detect the model.
        switch (vendor) {
            0x756e6547 => {
                detectIntelProcessor(&cpu, family, model, brand_id);
            },
            0x68747541 => {
                if (detectAMDProcessor(cpu, family, model)) |m| cpu.model = m;
            },
            else => {},
        }
    }

    // Add the CPU model's feature set into the working set, but then
    // override with actual detected features again.
    cpu.features.addFeatureSet(cpu.model.features);
    detectNativeFeatures(&cpu, os.tag);

    cpu.features.populateDependencies(cpu.arch.allFeaturesList());

    return cpu;
}

fn detectIntelProcessor(cpu: *Target.Cpu, family: u32, model: u32, brand_id: u32) void {
    if (brand_id != 0) {
        return;
    }
    switch (family) {
        3 => {
            cpu.model = &Target.x86.cpu.i386;
            return;
        },
        4 => {
            cpu.model = &Target.x86.cpu.i486;
            return;
        },
        5 => {
            if (cpu.has(.x86, .mmx)) {
                cpu.model = &Target.x86.cpu.pentium_mmx;
                return;
            }
            cpu.model = &Target.x86.cpu.pentium;
            return;
        },
        6 => {
            switch (model) {
                0x01 => {
                    cpu.model = &Target.x86.cpu.pentiumpro;
                    return;
                },
                0x03, 0x05, 0x06 => {
                    cpu.model = &Target.x86.cpu.pentium2;
                    return;
                },
                0x07, 0x08, 0x0a, 0x0b => {
                    cpu.model = &Target.x86.cpu.pentium3;
                    return;
                },
                0x09, 0x0d, 0x15 => {
                    cpu.model = &Target.x86.cpu.pentium_m;
                    return;
                },
                0x0e => {
                    cpu.model = &Target.x86.cpu.yonah;
                    return;
                },
                0x0f, 0x16 => {
                    cpu.model = &Target.x86.cpu.core2;
                    return;
                },
                0x17, 0x1d => {
                    cpu.model = &Target.x86.cpu.penryn;
                    return;
                },
                0x1a, 0x1e, 0x1f, 0x2e => {
                    cpu.model = &Target.x86.cpu.nehalem;
                    return;
                },
                0x25, 0x2c, 0x2f => {
                    cpu.model = &Target.x86.cpu.westmere;
                    return;
                },
                0x2a, 0x2d => {
                    cpu.model = &Target.x86.cpu.sandybridge;
                    return;
                },
                0x3a, 0x3e => {
                    cpu.model = &Target.x86.cpu.ivybridge;
                    return;
                },
                0x3c, 0x3f, 0x45, 0x46 => {
                    cpu.model = &Target.x86.cpu.haswell;
                    return;
                },
                0x3d, 0x47, 0x4f, 0x56 => {
                    cpu.model = &Target.x86.cpu.broadwell;
                    return;
                },
                0x4e, 0x5e, 0x8e, 0x9e, 0xa5, 0xa6 => {
                    cpu.model = &Target.x86.cpu.skylake;
                    return;
                },
                0xa7 => {
                    cpu.model = &Target.x86.cpu.rocketlake;
                    return;
                },
                0x55 => {
                    if (cpu.has(.x86, .avx512bf16)) {
                        cpu.model = &Target.x86.cpu.cooperlake;
                        return;
                    } else if (cpu.has(.x86, .avx512vnni)) {
                        cpu.model = &Target.x86.cpu.cascadelake;
                        return;
                    } else {
                        cpu.model = &Target.x86.cpu.skylake_avx512;
                        return;
                    }
                },
                0x66 => {
                    cpu.model = &Target.x86.cpu.cannonlake;
                    return;
                },
                0x7d, 0x7e => {
                    cpu.model = &Target.x86.cpu.icelake_client;
                    return;
                },
                0x6a, 0x6c => {
                    cpu.model = &Target.x86.cpu.icelake_server;
                    return;
                },
                0x8c, 0x8d => {
                    cpu.model = &Target.x86.cpu.tigerlake;
                    return;
                },
                0x97, 0x9a => {
                    cpu.model = &Target.x86.cpu.alderlake;
                    return;
                },
                0xbe => {
                    cpu.model = &Target.x86.cpu.gracemont;
                    return;
                },
                0xb7, 0xba, 0xbf => {
                    cpu.model = &Target.x86.cpu.raptorlake;
                    return;
                },
                0xaa, 0xac => {
                    cpu.model = &Target.x86.cpu.meteorlake;
                    return;
                },
                0xc5, 0xb5 => {
                    cpu.model = &Target.x86.cpu.arrowlake;
                    return;
                },
                0xc6 => {
                    cpu.model = &Target.x86.cpu.arrowlake_s;
                    return;
                },
                0xbd => {
                    cpu.model = &Target.x86.cpu.lunarlake;
                    return;
                },
                0xcc => {
                    cpu.model = &Target.x86.cpu.pantherlake;
                    return;
                },
                0xad => {
                    cpu.model = &Target.x86.cpu.graniterapids;
                    return;
                },
                0xae => {
                    cpu.model = &Target.x86.cpu.graniterapids_d;
                    return;
                },
                0xcf => {
                    cpu.model = &Target.x86.cpu.emeraldrapids;
                    return;
                },
                0x8f => {
                    cpu.model = &Target.x86.cpu.sapphirerapids;
                    return;
                },
                0x1c, 0x26, 0x27, 0x35, 0x36 => {
                    cpu.model = &Target.x86.cpu.bonnell;
                    return;
                },
                0x37, 0x4a, 0x4d, 0x5a, 0x5d, 0x4c => {
                    cpu.model = &Target.x86.cpu.silvermont;
                    return;
                },
                0x5c, 0x5f => {
                    cpu.model = &Target.x86.cpu.goldmont;
                    return;
                },
                0x7a => {
                    cpu.model = &Target.x86.cpu.goldmont_plus;
                    return;
                },
                0x86, 0x8a, 0x96, 0x9c => {
                    cpu.model = &Target.x86.cpu.tremont;
                    return;
                },
                0xaf => {
                    cpu.model = &Target.x86.cpu.sierraforest;
                    return;
                },
                0xb6 => {
                    cpu.model = &Target.x86.cpu.grandridge;
                    return;
                },
                0xdd => {
                    cpu.model = &Target.x86.cpu.clearwaterforest;
                    return;
                },
                0x57 => {
                    cpu.model = &Target.x86.cpu.knl;
                    return;
                },
                0x85 => {
                    cpu.model = &Target.x86.cpu.knm;
                    return;
                },
                else => return, // Unknown CPU Model
            }
        },
        15 => {
            if (cpu.has(.x86, .@"64bit")) {
                cpu.model = &Target.x86.cpu.nocona;
                return;
            }
            if (cpu.has(.x86, .sse3)) {
                cpu.model = &Target.x86.cpu.prescott;
                return;
            }
            cpu.model = &Target.x86.cpu.pentium4;
            return;
        },
        else => return, // Unknown CPU Model
    }
}

fn detectAMDProcessor(cpu: Target.Cpu, family: u32, model: u32) ?*const Target.Cpu.Model {
    return switch (family) {
        4 => &Target.x86.cpu.i486,
        5 => switch (model) {
            6, 7 => &Target.x86.cpu.k6,
            8 => &Target.x86.cpu.k6_2,
            9, 13 => &Target.x86.cpu.k6_3,
            10 => &Target.x86.cpu.geode,
            else => &Target.x86.cpu.pentium,
        },
        6 => if (cpu.has(.x86, .sse))
            &Target.x86.cpu.athlon_xp
        else
            &Target.x86.cpu.athlon,
        15 => if (cpu.has(.x86, .sse3))
            &Target.x86.cpu.k8_sse3
        else
            &Target.x86.cpu.k8,
        16, 18 => &Target.x86.cpu.amdfam10,
        20 => &Target.x86.cpu.btver1,
        21 => switch (model) {
            0x60...0x7f => &Target.x86.cpu.bdver4,
            0x30...0x3f => &Target.x86.cpu.bdver3,
            0x02, 0x10...0x1f => &Target.x86.cpu.bdver2,
            else => &Target.x86.cpu.bdver1,
        },
        22 => &Target.x86.cpu.btver2,
        23 => switch (model) {
            0x30...0x3f, 0x47, 0x60...0x6f, 0x70...0x7f, 0x84...0x87, 0x90...0x9f, 0xa0...0xaf => &Target.x86.cpu.znver2,
            else => &Target.x86.cpu.znver1,
        },
        25 => switch (model) {
            0x10...0x1f, 0x60...0x6f, 0x70...0x7f, 0xa0...0xaf => &Target.x86.cpu.znver4,
            else => &Target.x86.cpu.znver3,
        },
        26 => &Target.x86.cpu.znver5,
        else => null,
    };
}

fn detectNativeFeatures(cpu: *Target.Cpu, os_tag: Target.Os.Tag) void {
    var leaf = cpuid(0, 0);

    const max_level = leaf.eax;

    leaf = cpuid(1, 0);

    setFeature(cpu, .sse3, bit(leaf.ecx, 0));
    setFeature(cpu, .pclmul, bit(leaf.ecx, 1));
    setFeature(cpu, .ssse3, bit(leaf.ecx, 9));
    setFeature(cpu, .cx16, bit(leaf.ecx, 13));
    setFeature(cpu, .sse4_1, bit(leaf.ecx, 19));
    setFeature(cpu, .sse4_2, bit(leaf.ecx, 20));
    setFeature(cpu, .movbe, bit(leaf.ecx, 22));
    setFeature(cpu, .popcnt, bit(leaf.ecx, 23));
    setFeature(cpu, .aes, bit(leaf.ecx, 25));
    setFeature(cpu, .rdrnd, bit(leaf.ecx, 30));

    setFeature(cpu, .cx8, bit(leaf.edx, 8));
    setFeature(cpu, .cmov, bit(leaf.edx, 15));
    setFeature(cpu, .mmx, bit(leaf.edx, 23));
    setFeature(cpu, .fxsr, bit(leaf.edx, 24));
    setFeature(cpu, .sse, bit(leaf.edx, 25));
    setFeature(cpu, .sse2, bit(leaf.edx, 26));

    const has_xsave = bit(leaf.ecx, 27);
    const has_avx = bit(leaf.ecx, 28);

    // Make sure not to call xgetbv if xsave is not supported
    const xcr0: Xcr0 = if (has_xsave and has_avx) @bitCast(getXCR0()) else @bitCast(@as(u32, 0));

    const has_avx_save = xcr0.sse and xcr0.avx;

    // LLVM approaches avx512_save by hardcoding it to true on Darwin,
    // because the kernel saves the context even if the bit is not set.
    // https://github.com/llvm/llvm-project/blob/bca373f73fc82728a8335e7d6cd164e8747139ec/llvm/lib/Support/Host.cpp#L1378
    //
    // Google approaches this by using a different series of checks and flags,
    // and this may report the feature more accurately on a technically correct
    // but ultimately less useful level.
    // https://github.com/google/cpu_features/blob/b5c271c53759b2b15ff91df19bd0b32f2966e275/src/cpuinfo_x86.c#L113
    // (called from https://github.com/google/cpu_features/blob/b5c271c53759b2b15ff91df19bd0b32f2966e275/src/cpuinfo_x86.c#L1052)
    //
    // Right now, we use LLVM's approach, because even if the target doesn't support
    // the feature, the kernel should provide the same functionality transparently,
    // so the implementation details don't make a difference.
    // That said, this flag impacts other CPU features' availability,
    // so until we can verify that this doesn't come with side affects,
    // we'll say TODO verify this.

    // Darwin lazily saves the AVX512 context on first use: trust that the OS will
    // save the AVX512 context if we use AVX512 instructions, even if the bit is not
    // set right now.
    const has_avx512_save = if (os_tag.isDarwin())
        true
    else
        xcr0.zmm_hi256 and xcr0.hi16_zmm;

    // AMX requires additional context to be saved by the OS.
    const has_amx_save = xcr0.xtilecfg and xcr0.xtiledata;

    setFeature(cpu, .avx, has_avx_save);
    setFeature(cpu, .fma, bit(leaf.ecx, 12) and has_avx_save);
    // Only enable XSAVE if OS has enabled support for saving YMM state.
    setFeature(cpu, .xsave, bit(leaf.ecx, 26) and has_avx_save);
    setFeature(cpu, .f16c, bit(leaf.ecx, 29) and has_avx_save);

    leaf = cpuid(0x80000000, 0);
    const max_ext_level = leaf.eax;

    if (max_ext_level >= 0x80000001) {
        leaf = cpuid(0x80000001, 0);

        setFeature(cpu, .sahf, bit(leaf.ecx, 0));
        setFeature(cpu, .lzcnt, bit(leaf.ecx, 5));
        setFeature(cpu, .sse4a, bit(leaf.ecx, 6));
        setFeature(cpu, .prfchw, bit(leaf.ecx, 8));
        setFeature(cpu, .xop, bit(leaf.ecx, 11) and has_avx_save);
        setFeature(cpu, .lwp, bit(leaf.ecx, 15));
        setFeature(cpu, .fma4, bit(leaf.ecx, 16) and has_avx_save);
        setFeature(cpu, .tbm, bit(leaf.ecx, 21));
        setFeature(cpu, .mwaitx, bit(leaf.ecx, 29));

        setFeature(cpu, .@"64bit", bit(leaf.edx, 29));
    } else {
        for ([_]Target.x86.Feature{
            .sahf,
            .lzcnt,
            .sse4a,
            .prfchw,
            .xop,
            .lwp,
            .fma4,
            .tbm,
            .mwaitx,

            .@"64bit",
        }) |feat| {
            setFeature(cpu, feat, false);
        }
    }

    // Misc. memory-related features.
    if (max_ext_level >= 0x80000008) {
        leaf = cpuid(0x80000008, 0);

        setFeature(cpu, .clzero, bit(leaf.ebx, 0));
        setFeature(cpu, .rdpru, bit(leaf.ebx, 4));
        setFeature(cpu, .wbnoinvd, bit(leaf.ebx, 9));
    } else {
        for ([_]Target.x86.Feature{
            .clzero,
            .rdpru,
            .wbnoinvd,
        }) |feat| {
            setFeature(cpu, feat, false);
        }
    }

    if (max_level >= 0x7) {
        leaf = cpuid(0x7, 0);

        setFeature(cpu, .fsgsbase, bit(leaf.ebx, 0));
        setFeature(cpu, .sgx, bit(leaf.ebx, 2));
        setFeature(cpu, .bmi, bit(leaf.ebx, 3));
        // AVX2 is only supported if we have the OS save support from AVX.
        setFeature(cpu, .avx2, bit(leaf.ebx, 5) and has_avx_save);
        setFeature(cpu, .smep, bit(leaf.ebx, 7));
        setFeature(cpu, .bmi2, bit(leaf.ebx, 8));
        setFeature(cpu, .invpcid, bit(leaf.ebx, 10));
        setFeature(cpu, .rtm, bit(leaf.ebx, 11));
        // AVX512 is only supported if the OS supports the context save for it.
        setFeature(cpu, .avx512f, bit(leaf.ebx, 16) and has_avx512_save);
        setFeature(cpu, .evex512, bit(leaf.ebx, 16) and has_avx512_save);
        setFeature(cpu, .avx512dq, bit(leaf.ebx, 17) and has_avx512_save);
        setFeature(cpu, .rdseed, bit(leaf.ebx, 18));
        setFeature(cpu, .adx, bit(leaf.ebx, 19));
        setFeature(cpu, .smap, bit(leaf.ebx, 20));
        setFeature(cpu, .avx512ifma, bit(leaf.ebx, 21) and has_avx512_save);
        setFeature(cpu, .clflushopt, bit(leaf.ebx, 23));
        setFeature(cpu, .clwb, bit(leaf.ebx, 24));
        setFeature(cpu, .avx512pf, bit(leaf.ebx, 26) and has_avx512_save);
        setFeature(cpu, .avx512er, bit(leaf.ebx, 27) and has_avx512_save);
        setFeature(cpu, .avx512cd, bit(leaf.ebx, 28) and has_avx512_save);
        setFeature(cpu, .sha, bit(leaf.ebx, 29));
        setFeature(cpu, .avx512bw, bit(leaf.ebx, 30) and has_avx512_save);
        setFeature(cpu, .avx512vl, bit(leaf.ebx, 31) and has_avx512_save);

        setFeature(cpu, .prefetchwt1, bit(leaf.ecx, 0));
        setFeature(cpu, .avx512vbmi, bit(leaf.ecx, 1) and has_avx512_save);
        setFeature(cpu, .pku, bit(leaf.ecx, 4));
        setFeature(cpu, .waitpkg, bit(leaf.ecx, 5));
        setFeature(cpu, .avx512vbmi2, bit(leaf.ecx, 6) and has_avx512_save);
        setFeature(cpu, .shstk, bit(leaf.ecx, 7));
        setFeature(cpu, .gfni, bit(leaf.ecx, 8));
        setFeature(cpu, .vaes, bit(leaf.ecx, 9) and has_avx_save);
        setFeature(cpu, .vpclmulqdq, bit(leaf.ecx, 10) and has_avx_save);
        setFeature(cpu, .avx512vnni, bit(leaf.ecx, 11) and has_avx512_save);
        setFeature(cpu, .avx512bitalg, bit(leaf.ecx, 12) and has_avx512_save);
        setFeature(cpu, .avx512vpopcntdq, bit(leaf.ecx, 14) and has_avx512_save);
        setFeature(cpu, .rdpid, bit(leaf.ecx, 22));
        setFeature(cpu, .kl, bit(leaf.ecx, 23));
        setFeature(cpu, .cldemote, bit(leaf.ecx, 25));
        setFeature(cpu, .movdiri, bit(leaf.ecx, 27));
        setFeature(cpu, .movdir64b, bit(leaf.ecx, 28));
        setFeature(cpu, .enqcmd, bit(leaf.ecx, 29));

        // There are two CPUID leafs which information associated with the pconfig
        // instruction:
        // EAX=0x7, ECX=0x0 indicates the availability of the instruction (via the 18th
        // bit of EDX), while the EAX=0x1b leaf returns information on the
        // availability of specific pconfig leafs.
        // The target feature here only refers to the the first of these two.
        // Users might need to check for the availability of specific pconfig
        // leaves using cpuid, since that information is ignored while
        // detecting features using the "-march=native" flag.
        // For more info, see X86 ISA docs.
        setFeature(cpu, .uintr, bit(leaf.edx, 5));
        setFeature(cpu, .avx512vp2intersect, bit(leaf.edx, 8) and has_avx512_save);
        setFeature(cpu, .serialize, bit(leaf.edx, 14));
        setFeature(cpu, .tsxldtrk, bit(leaf.edx, 16));
        setFeature(cpu, .pconfig, bit(leaf.edx, 18));
        setFeature(cpu, .amx_bf16, bit(leaf.edx, 22) and has_amx_save);
        setFeature(cpu, .avx512fp16, bit(leaf.edx, 23) and has_avx512_save);
        setFeature(cpu, .amx_tile, bit(leaf.edx, 24) and has_amx_save);
        setFeature(cpu, .amx_int8, bit(leaf.edx, 25) and has_amx_save);

        if (leaf.eax >= 1) {
            leaf = cpuid(0x7, 0x1);

            setFeature(cpu, .sha512, bit(leaf.eax, 0));
            setFeature(cpu, .sm3, bit(leaf.eax, 1));
            setFeature(cpu, .sm4, bit(leaf.eax, 2));
            setFeature(cpu, .raoint, bit(leaf.eax, 3));
            setFeature(cpu, .avxvnni, bit(leaf.eax, 4) and has_avx_save);
            setFeature(cpu, .avx512bf16, bit(leaf.eax, 5) and has_avx512_save);
            setFeature(cpu, .cmpccxadd, bit(leaf.eax, 7));
            setFeature(cpu, .amx_fp16, bit(leaf.eax, 21) and has_amx_save);
            setFeature(cpu, .hreset, bit(leaf.eax, 22));
            setFeature(cpu, .avxifma, bit(leaf.eax, 23) and has_avx_save);

            setFeature(cpu, .avxvnniint8, bit(leaf.edx, 4) and has_avx_save);
            setFeature(cpu, .avxneconvert, bit(leaf.edx, 5) and has_avx_save);
            setFeature(cpu, .amx_complex, bit(leaf.edx, 8) and has_amx_save);
            setFeature(cpu, .avxvnniint16, bit(leaf.edx, 10) and has_avx_save);
            setFeature(cpu, .prefetchi, bit(leaf.edx, 14));
            setFeature(cpu, .usermsr, bit(leaf.edx, 15));
            setFeature(cpu, .avx10_1_256, bit(leaf.edx, 19));
            // APX
            setFeature(cpu, .egpr, bit(leaf.edx, 21));
            setFeature(cpu, .push2pop2, bit(leaf.edx, 21));
            setFeature(cpu, .ppx, bit(leaf.edx, 21));
            setFeature(cpu, .ndd, bit(leaf.edx, 21));
            setFeature(cpu, .ccmp, bit(leaf.edx, 21));
            setFeature(cpu, .cf, bit(leaf.edx, 21));
        } else {
            for ([_]Target.x86.Feature{
                .sha512,
                .sm3,
                .sm4,
                .raoint,
                .avxvnni,
                .avx512bf16,
                .cmpccxadd,
                .amx_fp16,
                .hreset,
                .avxifma,

                .avxvnniint8,
                .avxneconvert,
                .amx_complex,
                .avxvnniint16,
                .prefetchi,
                .usermsr,
                .avx10_1_256,
                .egpr,
                .push2pop2,
                .ppx,
                .ndd,
                .ccmp,
                .cf,
            }) |feat| {
                setFeature(cpu, feat, false);
            }
        }
    } else {
        for ([_]Target.x86.Feature{
            .fsgsbase,
            .sgx,
            .bmi,
            .avx2,
            .smep,
            .bmi2,
            .invpcid,
            .rtm,
            .avx512f,
            .evex512,
            .avx512dq,
            .rdseed,
            .adx,
            .smap,
            .avx512ifma,
            .clflushopt,
            .clwb,
            .avx512pf,
            .avx512er,
            .avx512cd,
            .sha,
            .avx512bw,
            .avx512vl,

            .prefetchwt1,
            .avx512vbmi,
            .pku,
            .waitpkg,
            .avx512vbmi2,
            .shstk,
            .gfni,
            .vaes,
            .vpclmulqdq,
            .avx512vnni,
            .avx512bitalg,
            .avx512vpopcntdq,
            .rdpid,
            .kl,
            .cldemote,
            .movdiri,
            .movdir64b,
            .enqcmd,

            .uintr,
            .avx512vp2intersect,
            .serialize,
            .tsxldtrk,
            .pconfig,
            .amx_bf16,
            .avx512fp16,
            .amx_tile,
            .amx_int8,

            .sha512,
            .sm3,
            .sm4,
            .raoint,
            .avxvnni,
            .avx512bf16,
            .cmpccxadd,
            .amx_fp16,
            .hreset,
            .avxifma,

            .avxvnniint8,
            .avxneconvert,
            .amx_complex,
            .avxvnniint16,
            .prefetchi,
            .usermsr,
            .avx10_1_256,
            .egpr,
            .push2pop2,
            .ppx,
            .ndd,
            .ccmp,
            .cf,
        }) |feat| {
            setFeature(cpu, feat, false);
        }
    }

    if (max_level >= 0xD and has_avx_save) {
        leaf = cpuid(0xD, 0x1);

        // Only enable XSAVE if OS has enabled support for saving YMM state.
        setFeature(cpu, .xsaveopt, bit(leaf.eax, 0));
        setFeature(cpu, .xsavec, bit(leaf.eax, 1));
        setFeature(cpu, .xsaves, bit(leaf.eax, 3));
    } else {
        for ([_]Target.x86.Feature{
            .xsaveopt,
            .xsavec,
            .xsaves,
        }) |feat| {
            setFeature(cpu, feat, false);
        }
    }

    if (max_level >= 0x14) {
        leaf = cpuid(0x14, 0);

        setFeature(cpu, .ptwrite, bit(leaf.ebx, 4));
    } else {
        for ([_]Target.x86.Feature{
            .ptwrite,
        }) |feat| {
            setFeature(cpu, feat, false);
        }
    }

    if (max_level >= 0x19) {
        leaf = cpuid(0x19, 0);

        setFeature(cpu, .widekl, bit(leaf.ebx, 2));
    } else {
        for ([_]Target.x86.Feature{
            .widekl,
        }) |feat| {
            setFeature(cpu, feat, false);
        }
    }

    if (max_level >= 0x24) {
        leaf = cpuid(0x24, 0);

        setFeature(cpu, .avx10_1_512, bit(leaf.ebx, 18));
    } else {
        for ([_]Target.x86.Feature{
            .avx10_1_512,
        }) |feat| {
            setFeature(cpu, feat, false);
        }
    }
}

const CpuidLeaf = packed struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

/// This is a workaround for the C backend until zig has the ability to put
/// C code in inline assembly.
extern fn zig_x86_cpuid(leaf_id: u32, subid: u32, eax: *u32, ebx: *u32, ecx: *u32, edx: *u32) callconv(.c) void;

fn cpuid(leaf_id: u32, subid: u32) CpuidLeaf {
    // valid for both x86 and x86_64
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    if (builtin.zig_backend == .stage2_c) {
        zig_x86_cpuid(leaf_id, subid, &eax, &ebx, &ecx, &edx);
    } else {
        asm volatile ("cpuid"
            : [_] "={eax}" (eax),
              [_] "={ebx}" (ebx),
              [_] "={ecx}" (ecx),
              [_] "={edx}" (edx),
            : [_] "{eax}" (leaf_id),
              [_] "{ecx}" (subid),
        );
    }

    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

/// This is a workaround for the C backend until zig has the ability to put
/// C code in inline assembly.
extern fn zig_x86_get_xcr0() callconv(.c) u32;

// Read control register 0 (XCR0). Used to detect features such as AVX.
fn getXCR0() u32 {
    if (builtin.zig_backend == .stage2_c) {
        return zig_x86_get_xcr0();
    }

    return asm volatile (
        \\ xor %%ecx, %%ecx
        \\ xgetbv
        : [_] "={eax}" (-> u32),
        :
        : .{ .edx = true, .ecx = true });
}
