/// The words a parameter's `id` may not be, as a closed list: the `id` is written as it is into the
/// `Parameters` struct the shader source declares (`ShaderSourceAssembly`), and the author reads it
/// as `params.<id>`.
///
/// - The keywords and alternative tokens of C++14, which Metal Shading Language is built on. The
///   compiler refuses most of them as a field name; `const`, `extern`, `mutable`, `static`,
///   `typedef` and `volatile` it reads as a declaration without a field, so the struct is one field
///   short. A size check does not see that when padding absorbs it (a dropped `float` before another
///   `float` and a `float4`), and the field after it then binds to the wrong offset, silently.
/// - Metal's own words: the qualifiers and the `as_type` operator, its reinterpreting cast. The
///   compiler already refuses `as_type` as a field name; it takes the qualifiers, but they are the
///   language's words and a later one may not, so a package that uses one should not be ready.
/// - The names of the types the struct text uses or Metal builds in (`uint`, `float2`, `float4`,
///   `half`, `bfloat`): a field named for one hides it from the fields after it, or is refused.
///   The other names Metal builds in (vector and matrix types such as `uint2`, atomic types, the
///   `metal` namespace, library functions such as `abs`) stay free: the struct text uses none of
///   them, so a field named for one compiles and sits at the layout's offset. The GPU smoke suite
///   pins one name of each family: `uint2`, `float2x2`, `atomic_uint`, `metal` and `abs`.
///
/// Names are case-sensitive, as the language is: `Kernel` is not `kernel`. The macros of the
/// standard headers (`NAN`, `FLT_MAX`, `M_PI_F`, ...) are not here; they are not keywords, there are
/// well over a hundred of them, and a field named for one is a compile error of the effect that names
/// the line, not a wrong binding.
enum MSLReservedWords {
    static func contains(_ word: String) -> Bool {
        all.contains(word)
    }

    static let all: Set<String> = Set(cxxKeywords + metalKeywords + typeNames)

    static let cxxKeywords = [
        "alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand", "bitor", "bool", "break", "case", "catch", "char", "char16_t", "char32_t",
        "class", "compl", "const", "const_cast", "constexpr", "continue", "decltype", "default", "delete", "do", "double", "dynamic_cast", "else",
        "enum", "explicit", "export", "extern", "false", "float", "for", "friend", "goto", "if", "inline", "int", "long", "mutable", "namespace",
        "new", "noexcept", "not", "not_eq", "nullptr", "operator", "or", "or_eq", "private", "protected", "public", "register", "reinterpret_cast",
        "return", "short", "signed", "sizeof", "static", "static_assert", "static_cast", "struct", "switch", "template", "this", "thread_local",
        "throw", "true", "try", "typedef", "typeid", "typename", "union", "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while",
        "xor", "xor_eq",
    ]

    static let metalKeywords = [
        "as_type", "constant", "device", "fragment", "kernel", "object_data", "ray_data", "thread", "threadgroup", "threadgroup_imageblock",
        "vertex",
    ]

    static let typeNames = ["bfloat", "float2", "float4", "half", "uint"]
}
