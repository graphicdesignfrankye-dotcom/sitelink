// Imposta l'icona personalizzata di un file. Uso: swift tools/set_file_icon.swift <icona.icns> <file>
import AppKit
let a = CommandLine.arguments
guard a.count == 3, let img = NSImage(contentsOfFile: a[1]) else { print("uso: set_file_icon <icns> <file>"); exit(1) }
exit(NSWorkspace.shared.setIcon(img, forFile: a[2], options: []) ? 0 : 2)
