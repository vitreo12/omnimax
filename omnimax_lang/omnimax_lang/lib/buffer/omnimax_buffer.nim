import omni_lang

#cpp file to compile together. Should I compile it ahead and use the link pragma on the .o instead?
{.compile: "omnimax_buffer.cpp".}

#Flags to cpp compiler
{.passC: "-O3".}

#Wrapping of cpp functions
proc get_buffer_Max(buf : pointer, fbufnum : cfloat) : pointer {.importc, cdecl.}

proc unlock_buffer_Max(buf : pointer) : void {.importc, cdecl.}

proc get_float_value_buffer_Max(buf : pointer, index : clong, channel : clong) : cfloat {.importc, cdecl.}

proc set_float_value_buffer_Max(buf : pointer, value : cfloat, index : clong, channel : clong) : void {.importc, cdecl.}

proc get_frames_buffer_Max(buf : pointer) : cint {.importc, cdecl.}

proc get_samples_buffer_Max(buf : pointer) : cint {.importc, cdecl.}

proc get_channels_buffer_Max(buf : pointer) : cint {.importc, cdecl.}

proc get_samplerate_buffer_Max(buf : pointer) : cdouble {.importc, cdecl.}

proc get_sampledur_buffer_Max(buf : pointer) : cdouble {.importc, cdecl.}

type
    Buffer_obj = object
        buf_ptr      : pointer                      #pointer to t_buffer_ref
        buf_data_ptr : ptr UncheckedArray[float32]  #actual float* data
        input_num*   : int                          #need to export it in order to be retrieved with the ins_Nim[buffer.input_num][0] syntax for get_buffer.

    Buffer* = ptr Buffer_obj

const
    exceeding_max_ugen_inputs = "ERROR: Buffer: exceeding maximum number of inputs: %d\n"
    upper_exceed_input_error  = "ERROR: Buffer: input %d out of bounds. Maximum input number is 32.\n"
    lower_exceed_input_error  = "ERROR: Buffer: input %d out of bounds. Minimum input number is 1.\n"

#Init buffer
proc innerInit*[S : SomeInteger](obj_type : typedesc[Buffer], input_num : S, omni_inputs : int) : Buffer =
    result = cast[Buffer](omni_alloc(cast[culong](sizeof(Buffer_obj))))

    #If these checks fail set to buf_ptr to nil, which will invalidate the Buffer (the get_buffer_Max would just return null)
    if input_num > omni_inputs:
        omni_print(exceeding_max_ugen_inputs, omni_inputs)

    elif input_num > 32:
        omni_print(upper_exceed_input_error, input_num)

    elif input_num < 1:
        omni_print(lower_exceed_input_error, input_num)

#Template which also uses the const omni_inputs, which belongs to the omni dsp new module. It will string substitute Buffer.init(1) with initInner(Buffer, 1, omni_inputs)
template new*[S : SomeInteger](obj_type : typedesc[Buffer], input_num : S) : untyped =
    innerInit(Buffer, input_num, omni_inputs) #omni_inputs belongs to the scope of the dsp module

proc destructor*(buffer : Buffer) : void =
    print("Calling Buffer's destructor")
    let buffer_ptr = cast[pointer](buffer)
    omni_free(buffer_ptr)

#Called at start of perform. If supernova is active, this will also lock the buffer.
proc get_buffer*(buffer : Buffer, fbufnum : float32) : void =
    discard

proc unlock_buffer*(buffer : Buffer) : void =
    unlock_buffer_Max(cast[pointer](buffer.buf_data_ptr))

##########
# GETTER #
##########

#1 channel
proc `[]`*[I : SomeNumber](a : Buffer, i : I) : float32 =
    return get_float_value_buffer_Max(a.buf_data_ptr, clong(i), clong(0))

#more than 1 channel
proc `[]`*[I1 : SomeNumber, I2 : SomeNumber](a : Buffer, i1 : I1, i2 : I2) : float32 =
    return get_float_value_buffer_Max(a.buf_data_ptr, clong(i1), clong(i2))

##########
# SETTER #
##########

#1 channel
proc `[]=`*[I : SomeNumber, S : SomeNumber](a : Buffer, i : I, x : S) : void =
    set_float_value_buffer_Max(a.buf_data_ptr, cfloat(x), clong(i), clong(0))

#more than 1 channel
proc `[]=`*[I1 : SomeNumber, I2 : SomeNumber, S : SomeNumber](a : Buffer, i1 : I1, i2 : I2, x : S) : void =
    set_float_value_buffer_Max(a.buf_data_ptr, cfloat(x), clong(i1), clong(i2))

#########
# INFOS #
#########

#length of each frame in buffer
proc len*(buffer : Buffer) : cint =
    return get_frames_buffer_Max(buffer.buf_data_ptr)

#Returns total size (buf_data_ptr->samples)
proc size*(buffer : Buffer) : cint =
    return get_samples_buffer_Max(buffer.buf_data_ptr)

#Number of channels
proc nchans*(buffer : Buffer) : cint =
    return get_channels_buffer_Max(buffer.buf_data_ptr)

#Samplerate (float64)
proc samplerate*(buffer : Buffer) : cdouble =
    return get_samplerate_buffer_Max(buffer.buf_data_ptr)

#Sampledur (Float64)
proc sampledur*(buffer : Buffer) : cdouble =
    return get_sampledur_buffer_Max(buffer.buf_data_ptr)