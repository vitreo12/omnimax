# MIT License
# 
# Copyright (c) 2020-2021 Francesco Cameli
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

version       = "0.3.0"
author        = "Francesco Cameli"
description   = "Max wrapper for omni."
license       = "MIT"

requires "nim >= 1.4.0"
requires "cligen >= 1.5.0"
requires "omni == 0.3.0"

#Ignore omnimax_lang
skipDirs = @["omnimax_lang"]

#Install omnimaxpkg
when defined(Windows):
    installDirs = @["omnimaxpkg"]

#nimble bug: can't install JitterAPI.framework and all its symbolic links
#gotta install just the folder containing all the files (JitterAPI.framework/Versions/A), and rebuild the links in the "after" hook
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

#Make sure omnimax_lang is getting installed first
before install:
    #getPkgDir() here points to the current omnimax source folder
    let package_dir = getPkgDir()
    
    #Update max-api submodule
    withDir(package_dir):
        echo "Updating the max-api repository..."
        exec "git submodule update --init --recursive"

    #Install omnimax_lang
    withDir(getPkgDir() & "/omnimax_lang"):
        exec "nimble install -Y"

#before / after are BOTH needed for any of the two to work
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
