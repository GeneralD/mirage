/// Port: MachBootstrapGateway (shared plumbing).
/// OS API: bootstrap_look_up / bootstrap_check_in / bootstrap_register, which
/// the Darwin overlay does not expose, so they are bound by symbol name.
import Darwin

@_silgen_name("bootstrap_look_up")
func bootstrapLookUp(_ bootstrap: mach_port_t, _ name: UnsafePointer<CChar>, _ port: UnsafeMutablePointer<mach_port_t>) -> kern_return_t

@_silgen_name("bootstrap_check_in")
func bootstrapCheckIn(_ bootstrap: mach_port_t, _ name: UnsafePointer<CChar>, _ port: UnsafeMutablePointer<mach_port_t>) -> kern_return_t

@_silgen_name("bootstrap_register")
func bootstrapRegister(_ bootstrap: mach_port_t, _ name: UnsafePointer<CChar>, _ port: mach_port_t) -> kern_return_t
