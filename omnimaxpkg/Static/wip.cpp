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
#define NUM_PARAMS 1
#define NUM_BUFFERS 1
#define NUM_OUTS 1
const std::array<std::string,NUM_INS> inputs_names = {"in1"};
const std::array<double,NUM_INS> inputs_defaults = {0.0};
const std::array<std::string,NUM_PARAMS> params_names = {"freq"};
const std::array<double,NUM_PARAMS> params_defaults = {440.0};
const std::array<std::string,NUM_BUFFERS> buffers_names = {"buf"};
const std::array<std::string,NUM_BUFFERS> buffers_defaults = {"hello"};
const std::array<std::string,NUM_OUTS> outputs_names = {"out1"};

//Used for attributes matching
std::array<t_object*,(NUM_PARAMS+NUM_BUFFERS)> attributes;

//global class pointer
static t_class* this_class = nullptr;

//Should they be atomic?
double max_samplerate = 0.0;
long   max_bufsize    = 0;

/*********/
/* print */
/*********/
void maxPrint_debug(const char* format_string, size_t value)
{
	post("%s %d", format_string, value);
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
	bool  omni_ugen_init;

	//These are used to collect params' settings when DSP is off.
	//Also helps when resetting samplerate, as a re-allocation of the omni object happens there
	double* current_param_vals;

	//Array of all t_buffer_ref*
	t_buffer_ref** buffer_refs;

	//Array of all symbols that buffer_refs point to. This is used to match buffers on notify
	t_symbol** buffer_refs_syms;
} t_omniobj;

/****************************/
/* omnimax buffer interface */
/****************************/
extern "C"
{
	void* get_buffer_ref_Max(void* max_object, char* buffer_name)
	{
		if(!max_object)
			return nullptr;
		
		for(int i = 0; i < NUM_BUFFERS; i++)
		{
			const char* buffer_name_entry = buffers_names[i].c_str();
			t_buffer_ref* buffer_ref = ((t_omniobj*)max_object)->buffer_refs[i];
			if(strcmp(buffer_name_entry, buffer_name) == 0)
				return (void*)buffer_ref;
		}

		return nullptr;
	}

	void* get_buffer_obj_Max(void* buffer_ref)
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
		buffer_setdirty(buffer);
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
void  omniobj_free(t_omniobj* self);
void  omniobj_assist(t_omniobj* self, void* unused, t_assist_function io, long index, char* string_dest);
void  omniobj_set(t_omniobj* self, t_symbol* s, long argc, t_atom* argv);
void  omniobj_perform64(t_omniobj* x, t_object* dsp64, double** ins, long numins, double** outs, long numouts, long sampleframes, long flags, void* userparam);
void  omniobj_dsp64(t_omniobj* self, t_object* dsp64, short *count, double samplerate, long maxvectorsize, long flags);
t_max_err omniobj_notify(t_omniobj* self, t_symbol *s, t_symbol *msg, void *sender, void *data);
t_max_err omniobj_attr_get(t_omniobj* self, t_object *attr, long *argc, t_atom **argv);
t_max_err omniobj_attr_set(t_omniobj* self, t_object *attr, long argc, t_atom *argv);

#define OMNI_CLASS_ATTR_ACCESSORS(c,attrname,getter,setter, index) \
        { t_object* theattr=(t_object* )class_attr_get(c,gensym(attrname)); \
			attributes[index]=theattr; \
            object_method(theattr,gensym("setmethod"), (void*)gensym("get"), (void*)getter); \
            object_method(theattr,gensym("setmethod"), (void*)gensym("set"), (void*)setter); }

//Main
void ext_main(void *r)
{
	this_class = class_new(OBJ_NAME, (method)omniobj_new, (method)omniobj_free, sizeof(t_omniobj), NULL, A_GIMME, 0);
	
	//Class methods
	class_addmethod(this_class, (method)omniobj_dsp64,	 "dsp64",  A_CANT,  0);
	class_addmethod(this_class, (method)omniobj_assist,  "assist", A_CANT,  0);
	class_addmethod(this_class, (method)omniobj_notify,  "notify", A_CANT,  0);
	class_addmethod(this_class, (method)omniobj_set,     "set",    A_GIMME, 0);

	//Attributes
	for(int i = 0; i < NUM_PARAMS; i++)
	{
		const char* param_name = params_names[i].c_str();
		CLASS_ATTR_DOUBLE(this_class, param_name, 0, t_omniobj, w_obj);
		CLASS_ATTR_LABEL(this_class, param_name, 0, param_name);
		OMNI_CLASS_ATTR_ACCESSORS(this_class, param_name, omniobj_attr_get, omniobj_attr_set, i);	
	}
	for(int i = 0; i < NUM_BUFFERS; i++)
	{
		const char* buffer_name = buffers_names[i].c_str();
		CLASS_ATTR_SYM(this_class, buffer_name, 0, t_omniobj, w_obj);
		CLASS_ATTR_LABEL(this_class, buffer_name, 0, buffer_name);
		OMNI_CLASS_ATTR_ACCESSORS(this_class, buffer_name, omniobj_attr_get, omniobj_attr_set, (i + NUM_PARAMS));	
	}
	
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
	t_omniobj *self = (t_omniobj*)object_alloc(this_class);

	//Allocate the omni_ugen.
	if(!self->omni_ugen)
	{
		self->omni_ugen = Omni_UGenAlloc();
		self->omni_ugen_init = false;
	}

	//Allocate memory for current_param_vals and set it to default values
	self->current_param_vals = (double*)malloc(NUM_PARAMS * sizeof(double));
	for(int i = 0; i < NUM_PARAMS; i++)
		self->current_param_vals[i] = params_defaults[i];

	//Allocate memory for all buffers, and set defaults when they != NIL
	self->buffer_refs = (t_buffer_ref**)malloc(NUM_BUFFERS * sizeof(t_buffer_ref*));
	self->buffer_refs_syms = (t_symbol**)malloc(NUM_BUFFERS * sizeof(t_symbol*));
	for(int i = 0; i < NUM_BUFFERS; i++)
	{
		t_symbol* buffer_default_sym;
		const char* buffer_default = buffers_defaults[i].c_str();
		
		if(strcmp(buffer_default, "NIL") != 0)	
			buffer_default_sym = gensym(buffer_default);
		else
			buffer_default_sym = gensym("");

		self->buffer_refs[i] = buffer_ref_new((t_object*)self, buffer_default_sym);
		self->buffer_refs_syms[i] = buffer_default_sym;
	}

	//Parse arguments. floats / ints set a param (in order). symbols set a buffer (in order)
	for(int i = 0; i < argc; i++)
	{
		t_atom* arg      = (argv + i);
		short   arg_type = arg->a_type;

		int param_counter  = 0;
		int buffer_counter = 0;

		//Set a param
		if(arg_type == A_LONG || arg_type == A_FLOAT)
		{	
			if(param_counter < NUM_PARAMS)
			{
				double arg_val;
				
				if(arg_type == A_LONG)
					arg_val = double(atom_getlong(arg));
				else
					arg_val = atom_getfloat(arg);
				
				Omni_UGenSetParam(self->omni_ugen, params_names[param_counter].c_str(), arg_val);
				self->current_param_vals[param_counter] = arg_val;
				param_counter += 1;
			}
		}

		//Set a buffer
		else if(arg_type == A_SYM)
		{
			if(buffer_counter < NUM_BUFFERS)
			{
				t_symbol* arg_val = atom_getsym(arg);
				buffer_ref_set(self->buffer_refs[buffer_counter], arg_val);
				//Don't run Omni_UGenSetBuffer, as Omni_UGenInit hasn't run yet
				self->buffer_refs_syms[buffer_counter] = arg_val;
				buffer_counter += 1;
			}
		}
	}

	//Inlets
	dsp_setup((t_pxobject*)self, NUM_INS);

	//Outlets
	for(int i = 0; i < NUM_OUTS; i++)
		outlet_new((t_object*)self, "signal");				

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
	
	//Free current_param_vals
	if(self->current_param_vals)
		free(self->current_param_vals);

	//Free buffer reference
	if(self->buffer_refs)
	{
		for(int i = 0; i < NUM_BUFFERS; i++)
		{
			t_buffer_ref* buffer_ref = self->buffer_refs[i];
			t_buffer_obj* buffer_obj = buffer_ref_getobject(buffer_ref);
			//If valid buffer
			if(buffer_obj)
				object_free(buffer_ref);
		}

		free(self->buffer_refs);
		free(self->buffer_refs_syms);
	}

	//Free dsp object
	dsp_free((t_pxobject*)self);
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
				inlet_name.append(inputs_names[i].c_str());
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
				outlet_name.append(outputs_names[i].c_str());
				strncpy(string_dest, outlet_name.c_str(), ASSIST_STRING_MAXSIZE);
				break;
			}
		}
	}
}

//Set param / buffer attribute style:
//freq 100 / buffer bufferName
t_max_err omniobj_attr_set(t_omniobj *self, t_object *attr, long argc, t_atom *argv)
{
	if(argc != 1)
		return MAX_ERR_NONE;

	for(int i = 0; i < (NUM_PARAMS + NUM_BUFFERS); i++)
	{
		//Match the correct attribute
		t_object* attribute = attributes[i];
		if(attribute == attr)
		{
			//Set a param
			if(i < NUM_PARAMS)
			{
				double param_val = atom_getfloat(argv);
				const char* param_name = params_names[i].c_str();
				Omni_UGenSetParam(self->omni_ugen, param_name, param_val);
				self->current_param_vals[i] = param_val;
			}
			//Set a buffer
			else
			{
				int i_offset = i - NUM_PARAMS;
				t_symbol* new_buffer_sym = atom_getsym(argv);
				buffer_ref_set(self->buffer_refs[i_offset], new_buffer_sym);
				if(self->omni_ugen_init)
					Omni_UGenSetBuffer(self->omni_ugen, buffers_names[i_offset].c_str(), "");
				self->buffer_refs_syms[i_offset] = new_buffer_sym;
			}
		}
	}

	return MAX_ERR_NONE;
}

//attr get, works with attrui
t_max_err omniobj_attr_get(t_omniobj* self, t_object *attr, long *argc, t_atom **argv)
{
	for(int i = 0; i < (NUM_PARAMS + NUM_BUFFERS); i++)
	{
		//Match the correct attribute
		t_object* attribute = attributes[i];
		if(attribute == attr)
		{
			char alloc;

			//Get a param
			if(i < NUM_PARAMS)
			{
				double val = self->current_param_vals[i];
				atom_alloc(argc, argv, &alloc);
				atom_setfloat(*argv, val);
			}
			//Get a buffer
			else
			{
				int i_offset = i - NUM_PARAMS;
				t_symbol* val = self->buffer_refs_syms[i_offset];
				atom_alloc(argc, argv, &alloc);
				atom_setsym(*argv, val);
			}
		}
	}
	
	return MAX_ERR_NONE;
}

//Send notification to buffer ref when something changes to the buffer (replaced, deleted, etc...)
t_max_err omniobj_notify(t_omniobj *self, t_symbol *s, t_symbol *msg, void *sender, void *data)
{
	//This is the buffer_name that received the message
	t_symbol* buffer_name_sym = (t_symbol*)object_method((t_object *)sender, gensym("getname"));

	//Look for the buffer_name in the buffer_refs array, and send the notify message to it
	for(int i = 0; i < NUM_BUFFERS; i++)
	{	
		t_buffer_ref* buffer_ref     = self->buffer_refs[i];
		t_symbol*     buffer_ref_sym = self->buffer_refs_syms[i];

		if(buffer_ref)
		{
			//Match the correct buffer and update omni's pointer
			if(buffer_ref_sym == buffer_name_sym)
			{
				t_max_err err = buffer_ref_notify(buffer_ref, s, msg, sender, data);
				if(self->omni_ugen_init)
					Omni_UGenSetBuffer(self->omni_ugen, buffers_names[i].c_str(), "");
				return err;
			}
				
		}
	}
	
	return MAX_ERR_NONE;
}

//Set a param:  "set freq 440"
//Set a buffer: "set buffer bufferName"
void omniobj_set_defer(t_omniobj* self, t_symbol* s, long argc, t_atom* argv)
{
	//freq 440 OR buffer bufferName
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
				double value;
				if(arg2_type == A_FLOAT)
					value = atom_getfloat(arg2);
				else
					value = double(atom_getlong(arg2));
				
				//Set param
				Omni_UGenSetParam(self->omni_ugen, arg1_char, value);

				//Store its value for DSP changes, like samplerate, which would re-allocate the Omni object
				for(int i = 0; i < NUM_PARAMS; i++)
				{
					const char* param_name = params_names[i].c_str();
					if(strcmp(param_name, arg1_char) == 0)
					{
						self->current_param_vals[i] = value;
						break;
					}
				}
			}

			//Set buffers, sym value
			else if(arg2_type = A_SYM)
			{
				t_symbol* new_buffer_sym = atom_getsym(arg2);
				
				//Find the correct buffer name and set its new value
				for(int i = 0; i < NUM_BUFFERS; i++)
				{
					const char* buffer_name = buffers_names[i].c_str();
					if(strcmp(buffer_name, arg1_char) == 0)
					{
						buffer_ref_set(self->buffer_refs[i], new_buffer_sym);
						if(self->omni_ugen_init)
							Omni_UGenSetBuffer(self->omni_ugen, buffer_name, "");
						self->buffer_refs_syms[i] = new_buffer_sym;
						break;
					}
				}
			}
		}
	}
}

//Set a param:  "set freq 440"
//Set a buffer: "set buffer bufferName"
void omniobj_set(t_omniobj* self, t_symbol* s, long argc, t_atom* argv)
{
	//if not in scheduler's thread, defer executes immediately (check docs)
	defer(self, (method)omniobj_set_defer, s, argc, argv);
}

//perform64
void omniobj_perform64(t_omniobj* self, t_object* dsp64, double** ins, long numins, double** outs, long numouts, long sampleframes, long flags, void* userparam)
{
	if(self->omni_ugen_init)
		Omni_UGenPerform64(self->omni_ugen, ins, outs, (int)sampleframes);
	else
	{
		for(int i = 0; i < numouts; i++)
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
	//get rid of previous object, allocate new one and re-init.
	if(((max_samplerate != samplerate) || max_bufsize != maxvectorsize) && self->omni_ugen && self->omni_ugen_init)
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
			const char* param_name = params_names[i].c_str();
			double param_val = self->current_param_vals[i];
			Omni_UGenSetParam(self->omni_ugen, param_name, param_val);
		}

		//Re-init the ugen
		self->omni_ugen_init = Omni_UGenInit(
			self->omni_ugen,  
			(int)maxvectorsize,
			samplerate, 
			(void*)self
		);
	}

	//Standard case, don't re-init object everytime dsp chain is recompiled, but just one time:
	//Data and structs need only to be allocated once!
	if(self->omni_ugen && !(self->omni_ugen_init))
	{
		//Change global samplerate and bufsize
		max_samplerate = samplerate;
		max_bufsize    = maxvectorsize;
		
		//init ugen
		self->omni_ugen_init = Omni_UGenInit(
			self->omni_ugen, 
			(int)maxvectorsize, 
			samplerate, 
			(void*)self
		);
	}

	//Update buffers (UGen must be init)
	if(self->omni_ugen_init)
	{
		for(int i = 0; i < NUM_BUFFERS; i++)
		{
			const char* buffer_name = buffers_names[i].c_str();
			Omni_UGenSetBuffer(self->omni_ugen, buffer_name, "");
		}
	}

	//Add dsp64 method
	object_method_direct(void, (t_object*, t_object*, t_perfroutine64, long, void*),
						 dsp64, gensym("dsp_add64"), (t_object*)self, (t_perfroutine64)omniobj_perform64, 0, NULL);
}