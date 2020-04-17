# MIT License
# 
# Copyright (c) 2020 Francesco Cameli
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

#[ All these functions are defined in the Max object cpp file ]#

import macros

#Retrieve buffer_ref*, or initialize one with random name
proc init_buffer_at_inlet(max_object : pointer, inlet : cint) : pointer {.importc, cdecl.}

#Retrive buffer_obj*
proc get_buffer_obj(buffer_ref : pointer) : pointer {.importc, cdecl.}

#Lock / Unlock
proc lock_buffer_Max(buffer_obj : pointer)   : ptr float {.importc, cdecl.}
proc unlock_buffer_Max(buffer_obj : pointer) : void      {.importc, cdecl.}

#Utilities
proc get_frames_buffer_Max(buffer_obj : pointer)     : clong   {.importc, cdecl.}
proc get_samples_buffer_Max(buffer_obj : pointer)    : clong   {.importc, cdecl.}
proc get_channels_buffer_Max(buffer_obj : pointer)   : clong   {.importc, cdecl.}
proc get_samplerate_buffer_Max(buffer_obj : pointer) : cdouble {.importc, cdecl.}
#proc get_sampledur_buffer_Max(buffer_obj : pointer) : cdouble {.importc, cdecl.}

type
    Buffer_obj = object
        max_object  : pointer                      #pointer to max's t_object
        buffer_ref  : pointer                      #pointer to t_buffer_ref
        buffer_obj  : pointer                      #pointer to t_buffer_obj
        buffer_data : ptr UncheckedArray[float32]  #actual float* data
        input_num*  : int                          #need to export it in order to be retrieved with the ins_Nim[buffer.input_num][0] syntax for get_buffer.
        length      : int
        size        : int
        chans       : int
        samplerate  : float

    Buffer* = ptr Buffer_obj

#Init buffer
proc struct_init_inner*[S : SomeInteger](obj_type : typedesc[Buffer], input_num : S, buffer_interface : pointer, ugen_auto_mem : ptr OmniAutoMem) : Buffer {.inline.} =
    #Just allocate the object. All max related init are done in get_buffer
    result = cast[Buffer](omni_alloc(culong(sizeof(Buffer_obj))))

    #Register this Buffer's memory to the ugen_auto_mem
    ugen_auto_mem.registerChild(result)

    #Assign the max object the buffer refers to
    result.max_object = buffer_interface

    #1 should be 0, 2 1, 3 2, etc... 32 31
    let real_input_num = int(input_num) - int(1)
    result.input_num   = real_input_num

    result.length = 0
    result.size = 0
    result.chans = 0
    result.samplerate = 0.0

    #Create the buffer_ref or get one if it was already created in Max from the args
    #This will return nullptr if max_object is nil or input number is out of bounds
    result.buffer_ref = init_buffer_at_inlet(result.max_object, cint(real_input_num))

    #If failed, set input num to 0 (which will then be picked by get_buffer(buffer, ins[0][0])). Minimum num of inputs in omni is 1 anyway (for now...)
    if isNil(result.buffer_ref):
        result.input_num = 0

#compile time check of input_num
macro checkInputNum*(input_num_typed : typed, omni_inputs_typed : typed) : untyped =
    let input_num_typed_kind = input_num_typed.kind
    
    if input_num_typed_kind != nnkIntLit:
        error("Buffer input_num must be expressed as an integer literal value")
    
    let 
        input_num = input_num_typed.intVal()
        omni_inputs = omni_inputs_typed.intVal()

    #If these checks fail set to sc_world to nil, which will invalidate the Buffer.
    #result.input_num is needed for get_buffer(buffer, ins[0][0), as 1 is the minimum number for ins, for now...
    if input_num > omni_inputs: 
        error("Buffer: \"input_num\"" & $input_num & " is out of bounds: maximum number of inputs: " & $omni_inputs)
    elif input_num < 1:
        error("Buffer: \"input_num\"" & $input_num & " is out of bounds: minimum input number is 1")

#Template which also uses the const omni_inputs, which belongs to the omni dsp new module. It will string substitute Buffer.init(1) with initInner(Buffer, 1, omni_inputs, ugen.buffer_interface_let)
template new*[S : SomeInteger](obj_type : typedesc[Buffer], input_num : S) : untyped =
    checkInputNum(input_num, omni_inputs)
    struct_init_inner(Buffer, input_num, buffer_interface, ugen_auto_mem) #omni_inputs AND buffer_interface belong to the scope of the dsp module and the body of the init function

#Called at start of perform. This should also lock the buffer.
proc get_buffer*(buffer : Buffer, input_val : float64) : bool {.inline.} =
    #This is safely changed in the max cpp wrapper
    let buffer_ref = buffer.buffer_ref
    if isNil(buffer_ref):
        buffer.buffer_obj = nil #reset it to nil if there's the need to unlock buffer
        return false

    let buffer_obj = get_buffer_obj(buffer_ref)
    if isNil(buffer_obj):
        buffer.buffer_obj = nil #reset it to nil if there's the need to unlock buffer
        return false

    #Buffer is good, lock it. If fails to look, return false
    let buffer_data   = cast[ptr UncheckedArray[float32]](lock_buffer_Max(buffer_obj))
    if isNil(cast[pointer](buffer_data)):
        buffer.buffer_obj = nil #reset it to nil if there's the need to unlock buffer
        return false
    
    #Check if buffer pointer has changed. If that's the case, update all the pointers and the values
    if buffer_obj != buffer.buffer_obj:
        buffer.buffer_obj  = buffer_obj
        buffer.buffer_data = buffer_data
        buffer.length      = int(get_frames_buffer_Max(buffer_obj))
        buffer.size        = int(get_samples_buffer_Max(buffer_obj))
        buffer.chans       = int(get_channels_buffer_Max(buffer_obj))
        buffer.samplerate  = float(get_samplerate_buffer_Max(buffer_obj))
    
    #All good, go on with the perform function
    return true

proc unlock_buffer*(buffer : Buffer) : void {.inline.} =
    #This check is needed as buffers could be unlocked when another one has been failed to acquire!
    if not isNil(buffer.buffer_obj):
        unlock_buffer_Max(buffer.buffer_obj)

##########
# GETTER #
##########

proc getter(buffer : Buffer, channel : int = 0, index : int = 0) : float {.inline.} =
    let chans = buffer.chans
    
    var actual_index : int
    
    if chans == 1:
        actual_index = index
    else:
        actual_index = (index * chans) + channel
    
    if actual_index >= 0 and actual_index < buffer.size:
        return float(buffer.buffer_data[actual_index])
    
    return float(0.0)

#1 channel
proc `[]`*[I : SomeNumber](a : Buffer, i : I) : float {.inline.} =
    return a.getter(0, int(i))

#more than 1 channel (i1 == channel, i2 == index)
proc `[]`*[I1 : SomeNumber, I2 : SomeNumber](a : Buffer, i1 : I1, i2 : I2) : float {.inline.} =
    return a.getter(int(i1), int(i2))

#linear interp read (1 channel)
proc read*[I : SomeNumber](buffer : Buffer, index : I) : float {.inline.} =
    let buf_len = buffer.length
    
    if buf_len <= 0:
        return 0.0

    let
        index_int = int(index)
        index1 : int = index_int mod buf_len
        index2 : int = (index1 + 1) mod buf_len
        frac : float  = float(index) - float(index_int)
    
    return float(linear_interp(frac, buffer.getter(0, index1), buffer.getter(0, index2)))

#linear interp read (more than 1 channel) (i1 == channel, i2 == index)
proc read*[I1 : SomeNumber, I2 : SomeNumber](buffer : Buffer, chan : I1, index : I2) : float {.inline.} =
    let buf_len = buffer.length

    if buf_len <= 0:
        return 0.0
    
    let 
        chan_int = int(chan)
        index_int = int(index)
        index1 : int = index_int mod buf_len
        index2 : int = (index1 + 1) mod buf_len
        frac : float  = float(index) - float(index_int)
    
    return float(linear_interp(frac, buffer.getter(chan_int, index1), buffer.getter(chan_int, index2)))

##########
# SETTER #
##########

proc setter[Y : SomeNumber](buffer : Buffer, channel : int = 0, index : int = 0, x : Y) : void {.inline.} =
    let chans = buffer.chans
    
    var actual_index : int
    
    if chans == 1:
        actual_index = index
    else:
        actual_index = (index * chans) + channel
    
    if actual_index >= 0 and actual_index < buffer.size:
        buffer.buffer_data[actual_index] = float32(x)

#1 channel
proc `[]=`*[I : SomeNumber, S : SomeNumber](a : Buffer, i : I, x : S) : void {.inline.} =
    a.setter(0, int(i), x)

#more than 1 channel (i1 == channel, i2 == index)
proc `[]=`*[I1 : SomeNumber, I2 : SomeNumber, S : SomeNumber](a : Buffer, i1 : I1, i2 : I2, x : S) : void {.inline.} =
    a.setter(int(i1), int(i2), x)

#########
# INFOS #
#########

#length of each frame in buffer
proc len*(buffer : Buffer) : int {.inline.} =
    return buffer.length

#Returns total size (frames * channels)
proc size*(buffer : Buffer) : int {.inline.} =
    return buffer.size

#Number of channels
proc chans*(buffer : Buffer) : int {.inline.} =
    return buffer.chans

#Samplerate (float64)
proc samplerate*(buffer : Buffer) : float {.inline.} =
    return buffer.samplerate

#Sampledur (Float64)
#proc sampledur*(buffer : Buffer) : float =
#    return float(get_sampledur_buffer_Max(buffer.buffer_obj))