# **omnimax**

Compile [omni](https://github.com/vitreo12/omni) code into [Max](https://cycling74.com/) `objects`.

## **Requirements**

1) [nim](https://nim-lang.org/)
2) [git](https://git-scm.com/)
3) [cmake](https://cmake.org/) 
4) [gcc](https://gcc.gnu.org/) (`Windows`)  /  [clang](https://clang.llvm.org/) (`MacOS`)

### **MacOS**

To install dependencies on MacOS it is suggested to use a package manager like [brew](https://brew.sh/). 

After `brew` has been installed, run the following command in the `Terminal` app to install `nim` and `cmake`:

    brew install nim cmake

Then, make sure that the `~/.nimble/bin` directory is set in your shell `$PATH`.
If using bash (the default shell in MacOS), you can simply run this command:

    echo "export PATH=\$PATH:~/.nimble/bin" >> ~/.bash_profile

### **Windows:**

On Windows, the [MinGW](http://mingw.org/)'s `gcc` compiler needs also to be installed.

To install dependencies on Windows it is suggested to use a package manager like [chocolatey](https://community.chocolatey.org/).

After `chocolatey` has been installed, open `PowerShell` as administrator and run this command to install `nim`, `git`, `cmake`, `make` and `mingw`:

    choco install nim git cmake make mingw -y

## **Installation**

To install `omnimax`, simply use the `nimble` package manager (it comes bundled with the `nim` installation).The command will also take care of installing `omni`:

    nimble install omnimax

## **Usage**

    omnimax ~/.nimble/pkgs/omni-0.3.0/examples/OmniSaw.omni

## **Website / Docs**

Check omni's [website](https://vitreo12.github.io/omni).