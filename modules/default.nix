{
  # Define all the modules that are available in the system
  # This explicit list serves as API documentation for library consumers
  flake.nixosModules = {
    system = ./system;
    desktop = ./desktop;
    development = ./development;
    hardware = ./hardware;
    graphics = ./graphics;
    networking = ./networking;
    pim = ./pim;
    users = ./users.nix;
    virt = ./virtualisation;
    desktopHardware = ./hardware/desktop.nix;
    laptopHardware = ./hardware/laptop.nix;
    crashDiagnostics = ./hardware/crash-diagnostics.nix;
    gaming = ./gaming;
    ai = ./ai;
    secrets = ./secrets;
    services = ./services;
    companion = ./companion;
    syncthing = ./syncthing;
    installer = ./installer;
    remoteDesktop = ./remote-desktop;
  };
}
