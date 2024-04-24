# Nup
A command-line tool for N-up processing of PDFs using macOS APIs, written in Swift.

# How to Compile
## 1. Install Xcode Command Line Tools

```sh
xcode-select --install
```

## 2. Download `Nup.swift`

```sh
curl https://raw.githubusercontent.com/doraTeX/Nup/main/Nup.swift > Nup.swift
```

## 3. Compile `Nup.swift`

```sh
swiftc Nup.swift
```

This will generate the `Nup` binary.

# Usage

```sh
./Nup [OPTIONS] <INPUT_PDF_PATH> <OUTPUT_PDF_PATH>
```

## Arguments

* `<INPUT_PDF_PATH>`:  Path to the input PDF file
* `<OUTPUT_PDF_PATH>`: Path to the output PDF file

## Options
* `--rows <ROWS>`:  Set the number of rows (default: `1`).
* `--columns <COLUMNS>`: Set the number of columns (default: `2`).
* `--direction <DIRECTION>`: Set the direction (default: `horizontalL2R`).
  * Valid directions:
     * `horizontalL2R`: From left to right, horizontally.
     * `horizontalR2L`: From right to left, horizontally.
     * `verticalL2R`: From top to bottom vertically, left to right horizontally.
     * `verticalR2L`: From top to bottom vertically, right to left horizontally.
* `-h`, `--help`: Show help information.

# Examples

```sh
$ Nup input.pdf output.pdf
$ Nup --rows 1 --columns 2 input.pdf output.pdf
$ Nup --direction horizontalR2L input.pdf output.pdf
```

# Details

See my [blog entry](https://doratex.hatenablog.jp/entry/) (in Japanese) for more information.

# License

[MIT License](./LICENSE)
