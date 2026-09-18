// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Glint",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "GlintCore", targets: ["GlintCore"]),
    .executable(name: "Glint", targets: ["Glint"]),
    .executable(name: "glint-bench", targets: ["GlintBench"]),
  ],
  targets: [
    .systemLibrary(name: "CZlib"),
    .systemLibrary(name: "CLibArchive"),
    .target(
      name: "CUnrar",
      exclude: ["vendor/license.txt", "vendor/acknow.txt", "vendor/readme.txt", "vendor/makefile"],
      sources: ["GlintUnrar.cpp"]
        + [
          "rar", "strlist", "strfn", "pathfn", "smallfn", "global", "file", "filefn", "filcreat",
          "archive", "arcread", "unicode", "system", "crypt", "crc", "rawread", "encname",
          "resource", "match", "timefn", "rdwrfn", "consio", "options", "errhnd", "rarvm",
          "secpassword", "rijndael", "getbits", "sha1", "sha256", "blake2s", "hash", "extinfo",
          "extract", "volume", "list", "find", "unpack", "headers", "threadpool", "rs16",
          "cmddata", "ui", "largepage", "filestr", "scantree", "dll", "qopen",
        ].map { "vendor/\($0).cpp" },
      publicHeadersPath: "include",
      cxxSettings: [.define("RARDLL"), .define("_FILE_OFFSET_BITS", to: "64")]
    ),
    .target(name: "GlintCore", dependencies: ["CZlib", "CLibArchive", "CUnrar"]),
    .executableTarget(name: "Glint", dependencies: ["GlintCore"]),
    .executableTarget(name: "GlintBench", dependencies: ["GlintCore"]),
    .testTarget(
      name: "GlintCoreTests", dependencies: ["GlintCore", "CZlib"], resources: [.copy("Fixtures")]),
    .testTarget(name: "GlintTests", dependencies: ["Glint", "GlintCore"]),
  ],
  swiftLanguageModes: [.v6],
  cxxLanguageStandard: .cxx17
)
