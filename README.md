This plugin uses clang for accurately completing C and C++ code.

## Installation

Use your favourite plugin manager or just drop all the files into the vim
folder. Without plugin manager with Linux and Mac:
```
git clone https://github.com/d86leader/clang_complete.git && cp -r clang_complete/* ~/.vim/
```
For Pathogen:
```
cd ~/.vim/bundle && git clone https://github.com/d86leader/clang_complete.git
```
For vim-plug and similar, add the following line to your vimrc file after initializing the manager:
```
Plug 'd86leader/clang_complete'
```

You need Vim 7.3 or higher, compiled with python support and ideally, with
the conceal feature.

## Minimum Configuration

- Set the `clang_library_path` to the directory containing file named
  libclang.{dll,so,dylib} (for Windows, Unix variants and OS X respectively) or
  the file itself, example:

```vim
 " path to directory where library can be found
 let g:clang_library_path='/usr/lib/llvm-3.8/lib'
 " or path directly to the library file
 let g:clang_library_path='/usr/lib64/libclang.so.3.8'
```

- Compiler options can be configured in a `.clang_complete` file in each project
  root.  Example of `.clang_complete` file:

```
-DDEBUG
-include ../config.h
-I../common
-I/usr/include/c++/4.5.3/
-I/usr/include/c++/4.5.3/x86_64-slackware-linux/
```

## Usage

This plugin provides an omnicompletion function. Set it as your c++ omnifunc:
```
setlocal omnifunc=ClangComplete
```
And then you can use it for completion with `C-x C-o`

## License

See doc/clang_complete.txt for help and license.
