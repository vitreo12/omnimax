version       = "0.1.0"
author        = "Francesco Cameli"
description   = "Max wrapper for omni."
license       = "MIT"

requires "nim >= 1.0.0"
requires "cligen >= 0.9.41"
requires "omni >= 0.1.0"

#Ignore omnimax_lang
skipDirs = @["omnimax_lang"]

#Install omnimaxpkg
when defined(Windows):
    installDirs = @["omnimaxpkg"]

#nimble bug: can't install JitterAPI.framework and all its symbolic links
#gotta install just the folder containing all the files (Versions/A), and rebuild the links in the "after" hook
else:
    installDirs  = @[
        "omnimaxpkg/JIT", 
        "omnimaxpkg/Static", 
        "omnimaxpkg/deps/max-api/include", 
        "omnimaxpkg/deps/max-api/script", 
        "omnimaxpkg/deps/max-api/site", 
        "omnimaxpkg/deps/max-api/lib/mac/JitterAPI.framework/Versions/A", 
    ] 

#Compiler executable
bin = @["omnimax"]

#If using "nimble install" instead of "nimble installOmniMax", make sure omnimax_lang is still getting installed
before install:
    #getPkgDir() here points to the current omnimax source folder
    withDir(getPkgDir() & "/omnimax_lang"):
        exec "nimble install"

#before/after are BOTH needed for any of the two to work
after install:
    #Nothing to do on Windows
    when defined(Windows):
        discard
    
    #On MacOS, reconstruct the JitterAPI.framework symbolic links
    else:
        #getPkgDir() here points to the one installed in .nimble/pkgs
        let jitter_api_framework_path = getPkgDir() & "/omnimaxpkg/deps/max-api/lib/mac/JitterAPI.framework"
        exec "ln -s " & $jitter_api_framework_path & "/Versions/A " & $jitter_api_framework_path & "/Versions/Current"
        exec "ln -s " & $jitter_api_framework_path & "/Versions/Current/Resources " & $jitter_api_framework_path & "/Resources"
        exec "ln -s " & $jitter_api_framework_path & "/Versions/Current/JitterAPI " & $jitter_api_framework_path & "/JitterAPI"

#As nimble install, but with -d:release, -d:danger and --opt:speed. Also installs omnimax_lang.
task installOmniMax, "Install the omnimax_lang package and the omnimax compiler":
    #Build and install the omnimax compiler executable. This will also trigger the "before install" to install omnimax_lang
    exec "nimble install --passNim:-d:release --passNim:-d:danger --passNim:--opt:speed"