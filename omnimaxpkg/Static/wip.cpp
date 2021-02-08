//cmake -G "MinGW Makefiles" -DOMNI_BUILD_DIR="../" -DOMNI_LIB_NAME="OmniSaw" -DC74_MAX_API_DIR="C:/Users/frank/.nimble/pkgs/omnimax-0.3.0/omnimaxpkg/deps/max-api" -DCMAKE_BUILD_TYPE=Release -DBUILD_MARCH="native" ..

#include <stdio.h>
#include <array>
#include <string>
#include "c74_msp.h"
#include "omni.h"

using namespace c74::max;
#define post(...)	object_post(NULL, __VA_ARGS__)

#define OBJ_NAME "libomnitest~"
#define NUM_INS 1
const std::array<std::string,1> input_names = {"in1"};
const std::array<double,1> input_defaults = {0.0};
#define NUM_PARAMS 1
const std::array<std::string,1> param_names = {"freq"};
const std::array<double,1> param_defaults = {440.0};
#define NUM_BUFFERS 0
const std::array<std::string,0> buffer_names = {};
const std::array<std::string,0> buffer_defaults = {};
#define NUM_OUTS 1
const std::array<std::string,1> output_names = {"out1"};

#define MAXIMUM_BUFFER_NAMES_LEN 100

//global class pointer
static t_class* this_class = nullptr;

//Should they be atomic?
double max_samplerate = 0.0;
long   max_bufsize    = 0;

/********************************/
/* print / samplerate / bufsize */
/********************************/
void maxPrint_debug(const char* format_string, size_t value)
{
	post("%s%d", format_string, value);
}

void maxPrint_str(const char* format_string)
{
	post("%s", format_string);
}

void maxPrint_float(float value)
{
	post("%f", value);
}

void maxPrint_int(int value)
{
	post("%d", value);
}

/**************/
/* Max struct */
/**************/
typedef struct _omniobj 
{
	t_pxobject w_obj;
	
	void* omni_ugen;
	bool  omni_ugen_is_init;

	//These are used to collect params' settings when DSP is off.
	//Also helps when resetting samplerate, as a re-allocation of the omni object happens there
	double* omni_current_set_param_vals;

	//Array of all t_buffer_ref*
	t_buffer_ref** buffer_refs;
} t_omniobj;

/****************************/
/* omnimax buffer interface */
/****************************/
extern "C"
{
	/* All these function already have checked the validity 
	of the buffer_ref AND buffer_obj pointers in omni, 
	no need to re-check it! */
	void* get_buffer_ref(void* max_object, char* buffer_name)
	{
		return nullptr;
	}

	void* get_buffer_obj(void* buffer_ref)
	{
		t_buffer_ref* buf_ref = (t_buffer_ref*)buffer_ref;
		return buffer_ref_getobject(buf_ref);
	}

	float* lock_buffer_Max(void* buffer_obj)
	{
		t_buffer_obj* buffer = (t_buffer_obj*)buffer_obj;
        return buffer_locksamples(buffer);
	}

	void unlock_buffer_Max(void* buffer_obj)
	{
		t_buffer_obj* buffer = (t_buffer_obj*)buffer_obj;
		buffer_unlocksamples(buffer);
	}

	long get_frames_buffer_Max(void* buffer_obj)
	{
		t_buffer_obj* buffer = (t_buffer_obj*)buffer_obj;
		return buffer_getframecount(buffer);
	}

	long get_channels_buffer_Max(void* buffer_obj)
	{
		t_buffer_obj* buffer = (t_buffer_obj*)buffer_obj;
		return buffer_getchannelcount(buffer);
	}

	double get_samplerate_buffer_Max(void* buffer_obj)
	{

		t_buffer_obj* buffer = (t_buffer_obj*)buffer_obj;
		return buffer_getsamplerate(buffer);
	}
}

/**************************/
/* Max template functions */
/**************************/
void* omniobj_new(t_symbol *s, long argc, t_atom *argv);
t_max_err omniobj_notify(t_omniobj *x, t_symbol *s, t_symbol *msg, void *sender, void *data);
void  omniobj_free(t_omniobj *x);
void  omniobj_float(t_omniobj *x, double f);
void  omniobj_int(t_omniobj *x, long n);
void  omniobj_assist(t_omniobj* self, void* unused, t_assist_function io, long index, char* string_dest);
void  omniobj_perform64(t_omniobj* x, t_object* dsp64, double** ins, long numins, double** outs, long numouts, long sampleframes, long flags, void* userparam);
void  omniobj_dsp64(t_omniobj* self, t_object* dsp64, short *count, double samplerate, long maxvectorsize, long flags);
void  omniobj_receive_message_any_inlet(t_omniobj* self, t_symbol* s, long argc, t_atom* argv);

//Main
void ext_main(void *r)
{
	this_class = class_new(OBJ_NAME, (method)omniobj_new, (method)omniobj_free, sizeof(t_omniobj), NULL, A_GIMME, 0);
	
	//class methods
	class_addmethod(this_class, (method)omniobj_dsp64,	 "dsp64",  A_CANT,  0);
	//class_addmethod(this_class, (method)omniobj_float,   "float",  A_FLOAT, 0);
	//class_addmethod(this_class, (method)omniobj_int,	 "int",    A_LONG,  0);
	class_addmethod(this_class, (method)omniobj_assist,  "assist", A_CANT,  0);
	//class_addmethod(this_class, (method)omniobj_notify,  "notify", A_CANT,  0);

	//Message to any inlet
	class_addmethod(this_class, (method)omniobj_receive_message_any_inlet, "anything", A_GIMME, 0);

	//Init all function pointers
	Omni_InitGlobal(
		(omni_alloc_func_t*)malloc, 
		(omni_realloc_func_t*)realloc, 
		(omni_free_func_t*)free, 
		(omni_print_debug_func_t*)maxPrint_debug, 
		(omni_print_str_func_t*)maxPrint_str,
		(omni_print_float_func_t*)maxPrint_float,  
		(omni_print_int_func_t*)maxPrint_int
	);
	
	class_dspinit(this_class);
	class_register(CLASS_BOX, this_class);
}

//New method looking at args
void *omniobj_new(t_symbol *s, long argc, t_atom *argv)
{
	//Alloc the object
	t_omniobj *self = (t_omniobj *)object_alloc(this_class);

	//Allocate the omni_ugen.
	if(!self->omni_ugen)
	{
		self->omni_ugen = Omni_UGenAlloc();
		self->omni_ugen_is_init = false;
	}

	//Allocate memory for omni_current_set_param_vals and set it to default values
	if(NUM_PARAMS > 0)
	{
		self->omni_current_set_param_vals = (double*)malloc(NUM_PARAMS * sizeof(double));
		for(int i = 0; i < NUM_PARAMS; i++)
			self->omni_current_set_param_vals[i] = param_defaults[i];
	}

	//Allocate memory for all buffers
	if(NUM_BUFFERS > 0) 
	{
		self->buffer_refs = (t_buffer_ref**)malloc(NUM_BUFFERS * sizeof(t_buffer_ref*));
		for(int i = 0; i < NUM_BUFFERS; i++)
		{
			//self->buffer_refs[i]
		}
	}

	//Parse arguments. floats / ints set a param (in order). symbols set a buffer (in order)
	for(int i = 0; i < argc; i++)
	{
		t_atom* arg      = (argv + i);
		short   arg_type = arg->a_type;

		int param_counter  = 0;
		int buffer_counter = 0;

		//Set a param
		if(arg_type == A_LONG)
		{
			double arg_val = double(atom_getlong(arg));
			Omni_UGenSetParam(self->omni_ugen, param_names[param_counter].c_str(), arg_val);
			self->omni_current_set_param_vals[param_counter] = arg_val;
			param_counter += 1;
		}

		//Set a param
		else if(arg_type == A_FLOAT)
		{
			double arg_val = atom_getfloat(arg);
			Omni_UGenSetParam(self->omni_ugen, param_names[param_counter].c_str(), arg_val);
			self->omni_current_set_param_vals[param_counter] = arg_val;
			param_counter += 1;
		}

		//Set a buffer
		else if(arg_type == A_SYM)
		{
			t_symbol* arg_val = atom_getsym(arg);
			buffer_counter += 1;
		}
	}

	//Inlets
	dsp_setup((t_pxobject *)self, NUM_INS);

	//Outlets
	for(int y = 0; y < NUM_OUTS; y++)
		outlet_new((t_object *)self, "signal");				

	//Necessary for no input / output buffers aliasing!
	self->w_obj.z_misc |= Z_NO_INPLACE;

	return self;
}

//free object
void omniobj_free(t_omniobj *self)
{
	//Free omni ugen
	if(self->omni_ugen)
		Omni_UGenFree(self->omni_ugen);

	//Free omni_current_set_param_vals
	if(self->omni_current_set_param_vals)
		free(self->omni_current_set_param_vals);

	//Free buffer references
	if(self->buffer_refs)
	{
		for(int i = 0; i < NUM_BUFFERS; i++)
		{
			t_buffer_ref* buffer_ref = self->buffer_refs[i];
			if(buffer_ref)
				object_free(buffer_ref);
		}

		free(self->buffer_refs);
	}

	//Free dsp object
	dsp_free((t_pxobject *)self);
}

//inlet/outlet names
void omniobj_assist(t_omniobj* self, void* unused, t_assist_function io, long index, char* string_dest)
{
	if (io == ASSIST_INLET) 
	{
		for(int i = 0; i < NUM_INS; i++)
		{
			if(i == index)
			{
				std::string inlet_name = "(signal) ";
				inlet_name.append(input_names[i].c_str());
				strncpy(string_dest, inlet_name.c_str(), ASSIST_STRING_MAXSIZE);
				break;
			}
		}
	}

	else if (io == ASSIST_OUTLET)
	{
		for(int i = 0; i < NUM_OUTS; i++)
		{
			if(i == index)
			{
				std::string outlet_name = "(signal) ";
				outlet_name.append(output_names[i].c_str());
				strncpy(string_dest, outlet_name.c_str(), ASSIST_STRING_MAXSIZE);
				break;
			}
		}
	}
}

//Set a param:  "set freq 440"
//Set a buffer: "set buffer bufferName"
void omniobj_receive_message_any_inlet_defer(t_omniobj* self, t_symbol* s, long argc, t_atom* argv)
{
	//inlet number
	long in = proxy_getinlet((t_object *)self);
	
	//message parser
	const char* message = s->s_name;
	
	//Check if message is "set"
	if(strcmp(message, "set") == 0)
	{	
		//"set param 0.5", "set buf bufferName"
		if(argc == 2)
		{
			t_atom* arg1 = argv;
			t_atom* arg2 = argv + 1;
			short arg1_type = arg1->a_type;
			short arg2_type = arg2->a_type;

			if(arg1_type == A_SYM)
			{
				const char* arg1_char = atom_getsym(arg1)->s_name; 

				//Set param, float values
				if(arg2_type == A_FLOAT || arg2_type == A_LONG)
				{	
					double arg2_double;
					if(arg2_type == A_FLOAT)
						arg2_double = atom_getfloat(arg2);
					else
						arg2_double = double(atom_getlong(arg2));
					
					//Set param
					Omni_UGenSetParam(self->omni_ugen, arg1_char, arg2_double);

					//Store its value for DSP changes, like samplerate, which would re-allocate the Omni object
					for(int i = 0; i < NUM_PARAMS; i++)
					{
						const char* param_name = param_names[i].c_str();
						if(strcmp(param_name, arg1_char) == 0)
						{
							self->omni_current_set_param_vals[i] = arg2_double;
							break;
						}
					}
				}

				//Set buffer names, sym value
				else if(arg2_type = A_SYM)
				{
					t_symbol* arg2_sym = atom_getsym(arg2);
				}
			}
		}
	}
}

//Set a param:  "set freq 440"
//Set a buffer: "set buffer bufferName"
void omniobj_receive_message_any_inlet(t_omniobj* self, t_symbol* s, long argc, t_atom* argv)
{
	//if not in scheduler's thread, defer executes immediately (check docs)
	defer(self, (method)omniobj_receive_message_any_inlet_defer, s, argc, argv);
}

//perform64
void omniobj_perform64(t_omniobj* self, t_object* dsp64, double** ins, long numins, double** outs, long numouts, long sampleframes, long flags, void* userparam)
{
	/* Actual audio loop in omni */
	if(self->omni_ugen_is_init)
		Omni_UGenPerform64(self->omni_ugen, ins, outs, (int)sampleframes);
	else
	{
		for (int i = 0; i < numouts; i++)
		{
			for(int y = 0; y < sampleframes; y++)
				outs[i][y] = 0.0;
		}
	}
}

//dsp64
void omniobj_dsp64(t_omniobj* self, t_object* dsp64, short *count, double samplerate, long maxvectorsize, long flags) 
{
	//Special case, if there is a change in samplerate or bufsize, and object has already been allocated and initialized, 
	//get rid of previous object, allocate new and re-init.
	if(((max_samplerate != samplerate) || max_bufsize != maxvectorsize) && self->omni_ugen && self->omni_ugen_is_init)
	{
		//Free, then re-alloc
		Omni_UGenFree(self->omni_ugen);
		self->omni_ugen = Omni_UGenAlloc();

		//Change samplerate and bufsize
		max_samplerate = samplerate;
		max_bufsize    = maxvectorsize;

		//Set correct param values again
		for(int i = 0; i < NUM_PARAMS; i++)
		{
			const char* param_name = param_names[i].c_str();
			double param_val = self->omni_current_set_param_vals[i];
			Omni_UGenSetParam(self->omni_ugen, param_name, param_val);
		}

		//Re-init the ugen
		int omni_successful_init = Omni_UGenInit(
			self->omni_ugen,  
			(int)maxvectorsize,
			samplerate, 
			(void*)self
		);
		
		self->omni_ugen_is_init  = omni_successful_init != 0;
	}

	//Standard case, don't re-init object everytime dsp chain is recompiled, but just one time:
	//Data and structs need only to be allocated once!
	if(self->omni_ugen && !(self->omni_ugen_is_init))
	{
		//Change samplerate and bufsize
		max_samplerate = samplerate;
		max_bufsize    = maxvectorsize;
		
		//init ugen
		int omni_successful_init = Omni_UGenInit(
			self->omni_ugen, 
			(int)maxvectorsize, 
			samplerate, 
			(void*)self
		);

		self->omni_ugen_is_init  = omni_successful_init != 0;
	}

	//Add dsp64 method
	object_method_direct(void, (t_object*, t_object*, t_perfroutine64, long, void*),
						 dsp64, gensym("dsp_add64"), (t_object*)self, (t_perfroutine64)omniobj_perform64, 0, NULL);
}