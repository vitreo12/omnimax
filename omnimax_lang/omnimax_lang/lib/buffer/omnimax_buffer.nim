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

import omni_lang/core/wrapper/omni_wrapper

#[ All these functions are defined in the Max object cpp file ]#
proc get_buffer_ref_Max(max_object : pointer, buffer_name : cstring) : pointer {.importc, cdecl.}
proc get_buffer_obj_Max(buffer_ref : pointer) : pointer {.importc, cdecl.}
proc lock_buffer_Max(buffer_obj : pointer)   : ptr float32 {.importc, cdecl.}
proc unlock_buffer_Max(buffer_obj : pointer) : void        {.importc, cdecl.}
proc get_frames_buffer_Max(buffer_obj : pointer)     : clong   {.importc, cdecl.}
proc get_channels_buffer_Max(buffer_obj : pointer)   : clong   {.importc, cdecl.}
proc get_samplerate_buffer_Max(buffer_obj : pointer) : cdouble {.importc, cdecl.}

#Create a new Buffer interface for the omnimax wrapper
omniBufferInterface:
    debug: false

    struct:
        buffer_ref  : pointer                      #pointer to t_buffer_ref
        buffer_obj  : pointer                      #pointer to t_buffer_obj
        buffer_data : ptr UncheckedArray[float32]  #pointer to float* data

    #(buffer_interface : pointer, buffer_name : cstring) -> void
    init:
        #Max object is passed via buffer_interface
        let max_object = buffer_interface

        #Get buffer_ref from max
        buffer.buffer_ref = get_buffer_ref_Max(max_object, buffer_name)

    #(buffer : Buffer, value : cstring) -> void
    update:
        let buffer_obj = get_buffer_obj_Max(buffer.buffer_ref)
        if buffer.buffer_obj != buffer_obj:
            buffer.buffer_obj = buffer_obj
            buffer.length = get_frames_buffer_Max(buffer_obj)
            buffer.samplerate = get_samplerate_buffer_Max(buffer_obj)
            buffer.channels = get_channels_buffer_Max(buffer_obj)
    
    #(buffer : Buffer) -> bool
    lock:
        let buffer_obj = buffer.buffer_obj
        if isNil(buffer_obj):
            return false

        let 
            buffer_data_ptr = cast[pointer](lock_buffer_Max(buffer_obj))
            buffer_data     = cast[ptr UncheckedArray[float32]](buffer_data_ptr)
        
        #Couldn't lock
        if isNil(buffer_data_ptr):
            return false

        #Set correct pointer to float32 data
        buffer.buffer_data = buffer_data

        return true
    
    #(buffer : Buffer) -> void
    unlock:
        unlock_buffer_Max(buffer.buffer_obj)

    #(buffer : Buffer, index : SomeInteger, channel : SomeInteger) -> float
    getter:
        let chans = buffer.channels
        
        var actual_index : int

        if chans == 1:
            actual_index = index
        else:
            actual_index = (index * chans) + channel
        
        if actual_index >= 0 and actual_index < buffer.size:
            return buffer.buffer_data[actual_index]
        
        return 0.0
    
    #(buffer : Buffer, x : SomeFloat, index : SomeInteger, channel : SomeInteger) -> void
    setter:
        let chans = buffer.channels
        
        var actual_index : int
        
        if chans == 1:
            actual_index = index
        else:
            actual_index = (index * chans) + channel
        
        if actual_index >= 0 and actual_index < buffer.size:
            buffer.buffer_data[actual_index] = float32(x)