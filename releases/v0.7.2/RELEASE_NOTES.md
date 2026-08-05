# Mod Translation Toolkit v0.7.2

## Critical startup fix
v0.7.0 and v0.7.1 could fail before showing the main window because the Creator ID UI introduced an invalid WPF `Border` layout.

The coverage row and Creator ID row are now wrapped in a single parent `StackPanel`, restoring valid WPF structure.
