#[ All these functions are defined in the Max object cpp file ]#

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

    Buffer* = ptr Buffer_obj

const
    exceeding_max_ugen_inputs = "ERROR: Buffer: exceeding maximum number of inputs: %d\n"
    upper_exceed_input_error  = "ERROR: Buffer: input %d out of bounds. Maximum input number is 32.\n"
    lower_exceed_input_error  = "ERROR: Buffer: input %d out of bounds. Minimum input number is 1.\n"

#Init buffer
proc innerInit*[S : SomeInteger](obj_type : typedesc[Buffer], input_num : S, omni_inputs : int, buffer_interface : pointer) : Buffer =
    #Just allocate the object. All max related init are done in get_buffer
    result = cast[Buffer](omni_alloc(cast[culong](sizeof(Buffer_obj))))

    #Assign the max object the buffer refers to
    result.max_object = buffer_interface

    #1 should be 0, 2 1, 3 2, etc... 32 31
    let real_input_num = int(input_num) - int(1)
    result.input_num   = real_input_num

    #Create the buffer_ref or get one if it was already created in Max from the args
    result.buffer_ref = init_buffer_at_inlet(result.max_object, cint(real_input_num))

    if input_num > omni_inputs:
        omni_print(exceeding_max_ugen_inputs, omni_inputs)

    elif input_num > 32:
        omni_print(upper_exceed_input_error, input_num)

    elif input_num < 1:
        omni_print(lower_exceed_input_error, input_num)

#Template which also uses the const omni_inputs, which belongs to the omni dsp new module. It will string substitute Buffer.init(1) with initInner(Buffer, 1, omni_inputs, ugen.buffer_interface_let)
template new*[S : SomeInteger](obj_type : typedesc[Buffer], input_num : S) : untyped =
    innerInit(Buffer, input_num, omni_inputs, buffer_interface) #omni_inputs AND user_buffer_interface belong to the scope of the dsp module and the body of the init function

proc destructor*(buffer : Buffer) : void =
    print("Calling Buffer's destructor")
    let buffer_ptr = cast[pointer](buffer)
    omni_free(buffer_ptr)

#Called at start of perform. This should also lock the buffer.
proc get_buffer*(buffer : Buffer, fbufnum : float32) : bool =
    let buffer_ref = buffer.buffer_ref
    if isNil(buffer_ref):
        #omni_print("INVALID BUFFER_REF")
        return false

    let buffer_obj    = get_buffer_obj(buffer_ref)
    buffer.buffer_obj = buffer_obj
    if isNil(buffer_obj):
        #omni_print("INVALID BUFFER_OBJ")
        return false
    
    let buffer_data    = cast[ptr UncheckedArray[float32]](lock_buffer_Max(buffer_obj))
    buffer.buffer_data = buffer_data
    if isNil(cast[pointer](buffer_data)):
        #omni_print("INVALID DATA")
        return false
    
    #All good, go on with the perform function
    return true

proc unlock_buffer*(buffer : Buffer) : void =
    unlock_buffer_Max(buffer.buffer_obj)

##########
# GETTER #
##########

#1 channel
proc `[]`*[I : SomeNumber](a : Buffer, i : I) : float32 =
    let 
        buf_data = a.buffer_data
        buf_obj  = a.buffer_obj
        index    = int(i)

    if index >= 0 and index < int(get_frames_buffer_Max(buf_obj)):
        return buf_data[index]

    return float32(0.0)

#more than 1 channel
proc `[]`*[I1 : SomeNumber, I2 : SomeNumber](a : Buffer, i1 : I1, i2 : I2) : float32 =
    let 
        buf_data = a.buffer_data
        buf_obj  = a.buffer_obj
        channel  = int(i2)
        index    = (int(i1) * channel) + channel

    if index >= 0 and index < int(get_samples_buffer_Max(buf_obj)):
        return buf_data[index]
    
    return float32(0.0)

##########
# SETTER #
##########

#1 channel
proc `[]=`*[I : SomeNumber, S : SomeNumber](a : Buffer, i : I, x : S) : void =
    var buf_data = a.buffer_data
    
    let 
        buf_obj = a.buffer_obj
        index   = int(i)
        value   = float32(x)

    if index >= 0 and index < int(get_frames_buffer_Max(buf_obj)):
        buf_data[index] = value

#more than 1 channel
proc `[]=`*[I1 : SomeNumber, I2 : SomeNumber, S : SomeNumber](a : Buffer, i1 : I1, i2 : I2, x : S) : void =
    var buf_data = a.buffer_data
    let 
        buf_obj = a.buffer_obj
        channel = int(i2)
        index   = (int(i1) * channel) + channel
        value   = float32(x)

    if index >= 0 and index < int(get_samples_buffer_Max(buf_obj)):
        buf_data[index] = value

#########
# INFOS #
#########

#length of each frame in buffer
proc len*(buffer : Buffer) : int {.inline.} =
    return int(get_frames_buffer_Max(buffer.buffer_obj))

#Returns total size (frames * channels)
proc size*(buffer : Buffer) : int {.inline.} =
    return int(get_samples_buffer_Max(buffer.buffer_obj))

#Number of channels
proc nchans*(buffer : Buffer) : int {.inline.} =
    return int(get_channels_buffer_Max(buffer.buffer_obj))

#Samplerate (float64)
proc samplerate*(buffer : Buffer) : float {.inline.} =
    return float(get_samplerate_buffer_Max(buffer.buffer_obj))

#Sampledur (Float64)
#proc sampledur*(buffer : Buffer) : float =
#    return float(get_sampledur_buffer_Max(buffer.buffer_obj))