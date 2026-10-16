fn main() {
    // Generate C# P/Invoke bindings directly into the Avalonia desktop project
    csbindgen::Builder::new()
        .input_extern_file("src/lib.rs")
        .csharp_class_name("NativeMethods")
        .csharp_namespace("RouletteStudio.Desktop.Native")
        .csharp_dll_name("daw_core")
        .generate_csharp_file("../../apps/desktop/RouletteStudio.Desktop/NativeMethods.g.cs")
        .unwrap();
}
