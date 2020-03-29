# **omnimax**

Compile [omni](https://github.com/vitreo12/omni) code into [Max](https://cycling74.com/) `objects`.

## **Requirements**

1) [nim](https://nim-lang.org/)
2) [git](https://git-scm.com/)
3) [cmake](https://cmake.org/) 
4) [gcc](https://gcc.gnu.org/) (`Windows`)  /  [clang](https://clang.llvm.org/) (`MacOS`)

### **MacOS**

To install dependencies on MacOS it is suggested to use a package manager like [brew](https://brew.sh/). 
To install `brew`, simply open the `Terminal` app and run this command :
    
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

After `brew` has been installed, run the following command in the `Terminal` app to install `nim` and `cmake`:

    brew install nim cmake

Then, make sure that the `~/.nimble/bin` directory is set in your shell `$PATH`.
If using bash (the default shell in MacOS), simply edit (or create if it doesn't exist) the `~/.bash_profile` file and add this line to it: 

    export PATH=$PATH:~/.nimble/bin

### **Windows:**

On Windows, the [MinGW](http://mingw.org/)'s `gcc` compiler needs also to be installed.

To install dependencies on Windows it is suggested to use a package manager like [scoop](https://scoop.sh/). 
To install `scoop`, simply open `PowerShell` and run this command :
    
    iwr -useb get.scoop.sh | iex

After `scoop` has been installed, run the following command in `PowerShell` to install `nim`, `git`, `cmake` and `gcc`:

    scoop install nim git cmake gcc

## **Installation**

First, install `omni`:

    git clone https://github.com/vitreo12/omni

    cd omni
        
    nimble installOmni

Then, install `omnimax`:

    git clone --recursive https://github.com/vitreo12/omnimax
    
    cd omnimax
    
    nimble installOmniMax

## **Usage**

    omnimax ~/.nimble/pkgs/omni_lang-0.1.0/omni_lang/examples/OmniSaw.omni                                                                                        