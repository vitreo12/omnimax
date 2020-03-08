version       = "0.1.0"
author        = "Francesco Cameli"
description   = "Max wrapper for omni."
license       = "MIT"

requires "nim >= 1.0.0"
requires "cligen >= 0.9.41"
requires "omni >= 0.1.0"

#Ignore omnimax_lang
skipDirs = @["omnimax_lang"]

#Install build/deps
installDirs = @["omnimaxpkg"] 

#Compiler executable
bin = @["omnimax"]

#If using "nimble install" instead of "nimble installOmniMax", make sure omnimax_lang is still getting installed
before install:
    withDir(getPkgDir() & "/omnimax_lang"):
        exec "nimble install"

#before/after are BOTH needed for any of the two to work
after install:
    discard

#As nimble install, but with -d:release, -d:danger and --opt:speed. Also installs omnimax_lang.
task installOmniMax, "Install the omnimax_lang package and the omnicollider compiler":
    #Build and install the omnicollider compiler executable. This will also trigger the "before install" to install omnimax_lang
    exec "nimble install --passNim:-d:release --passNim:-d:danger --passNim:--opt:speed"