# **omnimax**

Compile [omni](https://github.com/vitreo12/omni) code into [Max](https://cycling74.com/) `objects`.

## **Requirements**

1) [nim](https://nim-lang.org/)
2) [git](https://git-scm.com/)
3) [cmake](https://cmake.org/) 
4) [gcc](https://gcc.gnu.org/) (`Windows`)  /  [clang](https://clang.llvm.org/) (`MacOS`)

Note that omni only supports nim version 1.6.0. It is recommended to install it via [choosenim](https://github.com/dom96/choosenim).

## **Installation**

To install `omnimax`, simply use the `nimble` package manager (it comes bundled with the `nim` installation).The command will also take care of installing `omni`:

    nimble install omnimax -y

## **Usage**

    omnimax ~/.nimble/pkgs/omni-0.4.2/examples/OmniSaw.omni

## **Max object interface**

1. `ins` and `outs` represent audio inlets / outlets.
2. `params` and `buffers` can be set via messages and attributes. Consider this example:
       
    *MyOmniObject.omni*
    ```
    params:
        freq
        amp

    buffers:
        buf1
        buf2    

    ... implementation ...
    ```

    These `params` and `buffers` can be initialized on object instantiation. All numeric values will initialize `params`, and all symbol values will initialize `buffers`:

        [ myomniobject~ 440 foo 0.5 bar ]

    In the previous example, `freq == 440` / `amp == 0.5` / `buf1 == foo` / `buf2 == bar`.

    Another option is to use the attribute syntax:

        [ myomniobject~ @freq 440 @amp 0.5 @buf1 foo @buf2 bar ]

    One can also use `name $1` and `set name $1` messages to set the values of `params` and `buffers` at runtime:

        ( set freq 440 ) == ( freq 440 )
        ( set amp 0.5 )  == ( amp 0.5 )
        ( set buf1 foo ) == ( buf1 foo )
        ( set buf2 bar ) == ( buf1 bar )

    Finally, all `params` and `buffers` support the `attrui` object.

## **Website / Docs**

Check omni's [website](https://vitreo12.github.io/omni).
