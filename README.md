# ZEX DUMP

A `xxd` clone build with Zig Programming Language

## Features

- Display a file as hex, with offset and ascii format
- Customize bytes groupings, endianess, by offset and more..
- Revert the workflow! Take a hexdump and convert it back to binary format

## How to use

Clone this repo. Open the projects folder, and compile it
```sh
zig build
```
and access the binary inside *zig-out*
or, e.g.
```
zig build run -- binfile
```

## Roadmap

- [x] Basic `xxd` features, (autoskip, toggle offset, group size, endianess...)
- [ ] More complex things (outfile, output to C style, ...) **COMING SOON**

## Acknowledgments

This project was inspired by:

- Low Level Learning
- Coding Challenges
- `xxd` tool

## License

This project is under the [MIT License](./LICENSE).
