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

var OMNI_PROTO_INCLUDES = """
#include <stdio.h>
#include <array>
#include <string>
#include "c74_msp.h"
#include "omni.h"

using namespace c74::max;
#define post(...)	object_post(NULL, __VA_ARGS__)

"""

var OMNI_PROTO_CPP = """ 

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

double get_maxSamplerate()
{
	return max_samplerate;
}

int get_maxBufSize()
{
	return (int)max_bufsize;
}

/**************/
/* Max struct */
/**************/
typedef struct _omniobj 
{
	t_pxobject w_obj;
	
	void* omni_ugen;
	bool  omni_ugen_is_init;

	//These are used to pass arguments to the init function (in1, in2, etc...)
	double*  input_vals;
	double** args;

	//This won't store boolean values, but the input numbers that are at audio rate.
	int* control_rate_inlets;

	//Used for control_rate_inlets
	double** control_rate_arrays;

	//Array of possible buffers and array of their names (used to parse the notify callback!!)
	t_buffer_ref** buffer_refs_array;
	char** 		   buffer_names_array;
} t_omniobj;

/****************************/
/* omnimax buffer interface */
/****************************/
extern "C"
{
	//Called in init
	void* init_buffer_at_inlet(void* max_object, int inlet)
	{
		if(!max_object)
			return nullptr;

		t_buffer_ref* buffer_ref = nullptr;
		
		//These two checks down here are useless (tested already), remove them ASAP!
		if(inlet >= 0 && inlet < NUM_INS)
		{
			t_omniobj* self = (t_omniobj*)max_object;
			buffer_ref = self->buffer_refs_array[inlet];

			//If not initialized already, initialize it with a random identifier.
			if(!buffer_ref)
			{
				post("Non-initialized buffer_ref. Doing it now!");

				t_symbol* unique_name = symbol_unique();
				buffer_ref = buffer_ref_new((t_object*)self, unique_name);
				self->buffer_refs_array[inlet] = buffer_ref;

				self->buffer_names_array[inlet] = (char*)malloc(MAXIMUM_BUFFER_NAMES_LEN * sizeof(char));
				strcpy(self->buffer_names_array[inlet], unique_name->s_name); 
			}

			post("Init buffer: %p", (void*)buffer_ref);
		}
		
		return (void*)buffer_ref;
	}

	/* All these function already have checked the validity 
	of the buffer_ref AND buffer_obj pointers in omni, 
	no need to re-check it! */
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

	long get_samples_buffer_Max(void* buffer_obj)
	{
		t_buffer_obj* buffer = (t_buffer_obj*)buffer_obj;
		return buffer_getframecount(buffer) * buffer_getchannelcount(buffer);
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
	class_addmethod(this_class, (method)omniobj_float,	 "float",  A_FLOAT, 0);
	class_addmethod(this_class, (method)omniobj_int,	 "int",    A_LONG,  0);
	class_addmethod(this_class, (method)omniobj_assist, "assist", A_CANT,  0);
	class_addmethod(this_class, (method)omniobj_notify, "notify", A_CANT,  0);

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
		(omni_print_int_func_t*)maxPrint_int,  
		(omni_get_samplerate_func_t*)get_maxSamplerate,
		(omni_get_bufsize_func_t*)get_maxBufSize
	);
	
	class_dspinit(this_class);
	class_register(CLASS_BOX, this_class);
}

//New method looking at args
void *omniobj_new(t_symbol *s, long argc, t_atom *argv)
{
	//Alloc the object
	t_omniobj *self = (t_omniobj *)object_alloc(this_class);

	//Allocate memory for eventual buffers (this should actually just be allocated if there are buffers, this is just easier now)
	self->buffer_refs_array = (t_buffer_ref**)malloc(NUM_INS * sizeof(t_buffer_ref*));

	//Allocate memory for buffers names (needed in the notify function!)
	self->buffer_names_array = (char**)malloc(NUM_INS * sizeof(char*));

	//These are used when sending float/int messages in inlets instead of signals
	self->input_vals = (double*)malloc(NUM_INS * sizeof(double));
	self->control_rate_inlets = (int*)malloc(NUM_INS * sizeof(int));
	self->control_rate_arrays = (double**)malloc(NUM_INS * sizeof(double*));

	//Allocate memory for args to passed to init
	self->args = (double**)malloc(NUM_INS * sizeof(double*));

	//Init various arrays
	for(int i = 0; i < NUM_INS; i++)
	{
		//Allocate for all arguments.. Can't be bothered doing maths here
		double* arg_ptr = (double*)malloc(sizeof(double));
		self->args[i]   = arg_ptr;

		//Initialize with default values'array
		self->input_vals[i] = default_vals[i];
		
		//Unchecked inlets (yet). Will be checked at the start of dsp function.
		self->control_rate_inlets[i] = -1;

		//Initialize buf_refs and buf_names to nullptr! This is essential!
		self->buffer_refs_array[i]   = nullptr;
		self->buffer_names_array[i]  = nullptr;
		self->control_rate_arrays[i] = nullptr;
	}

	//Parse arguments!
	for(int y = 0; y < argc; y++)
	{
		//Execute only if y < NUM_INS
		if(y >= NUM_INS)
			break;

		t_atom* arg      = (argv + y);
		short   arg_type = arg->a_type;

		//numbers are passed to init via self->args, and also used to initialize input_vals.
		if(arg_type == A_LONG)
		{
			double arg_val = double(atom_getlong(arg));
			self->args[y][0] = arg_val;
			self->input_vals[y] = arg_val;

			post("arg %d: %f", y, arg_val);
		}

		else if(arg_type == A_FLOAT)
		{
			double arg_val = atom_getfloat(arg);
			self->args[y][0] = arg_val;
			self->input_vals[y] = arg_val;

			post("arg %d: %f", y, arg_val);
		}

		//symbols are used to initialize buffers!
		else if(arg_type == A_SYM)
		{
			t_symbol* arg_val          = atom_getsym(arg);
			t_buffer_ref* buffer_ref   = buffer_ref_new((t_object*)self, arg_val);
			self->buffer_refs_array[y] = buffer_ref;

			post("arg %d: %s", y, arg_val->s_name);

			self->buffer_names_array[y] = (char*)malloc(MAXIMUM_BUFFER_NAMES_LEN * sizeof(char));
			strcpy(self->buffer_names_array[y], arg_val->s_name); 
		}
	}

	//Allocate omni_ugen.
	if(!self->omni_ugen)
	{
		self->omni_ugen = Omni_UGenAlloc();
		self->omni_ugen_is_init = false;
	}

	//Inlets
	dsp_setup((t_pxobject *)self, NUM_INS);

	//Outlets
	for(int y = 0; y < NUM_OUTS; y++)
		outlet_new((t_object *)self, "signal");				

	//Necessary for no buffer aliasing!
	self->w_obj.z_misc |= Z_NO_INPLACE;

	return self;
}

//free object
void omniobj_free(t_omniobj *self)
{
	//Free omni ugen
	if(self->omni_ugen)
		Omni_UGenFree(self->omni_ugen);

	//Free double arguments
	if(self->args)
	{
		for(int i = 0; i < NUM_INS; i++)
		{
			double* arg_ptr = self->args[i];
			if(arg_ptr)
				free(arg_ptr);
		}

		free(self->args);
	}

	//Free input_vals
	if(self->input_vals)
		free(self->input_vals);

	if(self->control_rate_inlets)
		free(self->control_rate_inlets);

	if(self->control_rate_arrays)
	{
		for(int h = 0; h < NUM_INS; h++)
		{
			double* control_rate_array = self->control_rate_arrays[h];
			if(control_rate_array)
				free(control_rate_array);
		}

		free(self->control_rate_arrays);
	}

	//Free buffer references
	if(self->buffer_refs_array)
	{
		for(int y = 0; y < NUM_INS; y++)
		{
			t_buffer_ref* buffer_ref = self->buffer_refs_array[y];
			if(buffer_ref)
				object_free(buffer_ref);
		}

		free(self->buffer_refs_array);
	}

	//Free buffer names array
	if(self->buffer_names_array)
	{
		for(int z = 0; z < NUM_INS; z++)
		{
			char* buffer_name = self->buffer_names_array[z];
			if(buffer_name)
				free(buffer_name);
		}

		free(self->buffer_names_array);
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
				std::string inlet_name = "(signal/float/symbol) ";
				inlet_name.append(inlet_names[i].c_str());
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
				outlet_name.append(outlet_names[i].c_str());
				strncpy(string_dest, outlet_name.c_str(), ASSIST_STRING_MAXSIZE);
				break;
			}
		}
	}
}

//Send notification to buffer ref when something changes to the buffer (replaced, deleted, etc...)
t_max_err omniobj_notify(t_omniobj *x, t_symbol *s, t_symbol *msg, void *sender, void *data)
{
	//This is the buffer_name that received the message
	t_symbol* buffer_name = (t_symbol *)object_method((t_object *)sender, gensym("getname"));

	post("NOTIFY: received message %s for buffer name %s", msg->s_name, buffer_name->s_name);

	//Look for the buffer_name in the buffer array, to send the notify message to it
	for(int i = 0; i < NUM_INS; i++)
	{	
		t_buffer_ref* current_buffer_ref = x->buffer_refs_array[i];
		char* current_buffer_name = x->buffer_names_array[i];

		if(current_buffer_ref)
		{
			post("buffer name: %s", buffer_name->s_name);
			post("current_buffer_name: %s", current_buffer_name);
			
			//Found the buffer! Send the notification to it.
			if(strcmp(buffer_name->s_name, current_buffer_name) == 0)
			{
				post("NOTIFY buffer with name %s with message %s", current_buffer_name, msg->s_name);
				return buffer_ref_notify(current_buffer_ref, s, msg, sender, data);
			}
		}
	}
	
	return 0;
}

//Float on any inlet
void omniobj_float(t_omniobj *x, double f)
{
	long inlet = proxy_getinlet((t_object *)x);
	
	if(x->input_vals)
		x->input_vals[inlet] = f; 
}

//Int on any inlet
void omniobj_int(t_omniobj *x, long f)
{
	omniobj_float(x, double(f));
}

//deferred function
void set_buffer_at_inlet(t_omniobj* self, long inlet, t_symbol* name)
{	
	t_buffer_ref* buffer_ref = self->buffer_refs_array[inlet];
	if(buffer_ref)
	{
		post("Modifying buffer: %p", (void*)buffer_ref);
		
		//Change reference
		buffer_ref_set(buffer_ref, name);
		
		//And update buffer names array entry
		strcpy(self->buffer_names_array[inlet], name->s_name); 
	}

	//If no buffer_ref, create a new one with the right name
	else
	{
		buffer_ref = buffer_ref_new((t_object*)self, name);
		self->buffer_refs_array[inlet] = buffer_ref;

		self->buffer_names_array[inlet] = (char*)malloc(MAXIMUM_BUFFER_NAMES_LEN * sizeof(char));
		strcpy(self->buffer_names_array[inlet], name->s_name); 
		
		post("Initialized buffer: %p", (void*)buffer_ref);
	}

	//long buffer_channels = buffer_getchannelcount(buffer_ref_getobject(buffer_ref));
	//if(buffer_channels > 1)
	//	post("WARNING: The %s buffer has %d channels.", name->s_name, buffer_channels);
}

void omniobj_receive_message_any_inlet_defer(t_omniobj* self, t_symbol* s, long argc, t_atom* argv)
{
	//inlet number
	long in = proxy_getinlet((t_object *)self);
	
	//message parser
	const char* message = s->s_name;
	
	//Check if message is "set"
	if(strcmp(message, "set") == 0)
	{	
		//"set bufferName" (at specific inlet)
		if(argc == 1)
		{
			short arg_type = argv->a_type;
			if(arg_type == A_SYM)
			{	
				t_symbol* arg_sym = atom_getsym(argv);
				const char* arg_char = arg_sym->s_name;
				post("Set message at inlet %d: %s", in, arg_char);
				set_buffer_at_inlet(self, in, arg_sym);
			}
		}

		//"set in1 bufferName", "set buf bufferName"
		else if(argc == 2)
		{
			t_atom* arg1 = argv;
			t_atom* arg2 = argv + 1;
			short arg1_type = arg1->a_type;
			short arg2_type = arg2->a_type;

			if(arg1_type == A_SYM)
			{
				const char* arg1_char = atom_getsym(arg1)->s_name; 

				//Set float values
				if(arg2_type == A_FLOAT || arg2_type == A_LONG)
				{
					for(int i = 0; i < inlet_names.size(); i++)
					{
						const char* input_name_str = inlet_names[i].c_str();

						//if message name equals to one of the inlet names, set float value at that specific inlet
						if(strcmp(arg1_char, input_name_str) == 0)
						{
							double arg2_double;

							if(arg2_type == A_FLOAT)
								arg2_double = atom_getfloat(arg2);
							else
								arg2_double = double(atom_getlong(arg2));
							
							if(self->input_vals)
								self->input_vals[i] = arg2_double; 

							post("Set %s %f", arg1_char, arg2_double);
							break;
						}
					}
				}

				//Set buffer names
				else if(arg2_type = A_SYM)
				{
					t_symbol* arg2_sym = atom_getsym(arg2);

					for(int i = 0; i < inlet_names.size(); i++)
					{
						const char* input_name_str = inlet_names[i].c_str();

						//if message name equals to one of the inlet names, set buffer value at that specific inlet
						if(strcmp(arg1_char, input_name_str) == 0)
						{
							set_buffer_at_inlet(self, i, arg2_sym);
							post("Set %s %s", arg1_char, arg2_sym->s_name);
							break;
						}
					}
				}
			}
		}
	}

	//Symbol is the message: "bufferName"
	else
	{
		post("Direct symbol message at inlet %d: %s", in, message);
		set_buffer_at_inlet(self, in, s);
	}
}

//Received at any inlet!
//Format: 
//either send a symbol to the specific correct inlet to modify the buffer,
//OR send a "set in1 bufferName" to any inlet to set specific "in1" buffer to "bufferName".
void omniobj_receive_message_any_inlet(t_omniobj* self, t_symbol* s, long argc, t_atom* argv)
{
	defer(self, (method)omniobj_receive_message_any_inlet_defer, s, argc, argv);
}

//perform64
void omniobj_perform64(t_omniobj* self, t_object* dsp64, double** ins, long numins, double** outs, long numouts, long sampleframes, long flags, void* userparam)
{
	/* Convert non-audio rate inlets to audio rate.. This is NOT optimized at all... */
	//if there is at least one control inlet
	if(self->control_rate_inlets[0] >= 0)
	{
		for(int i = 0; i < NUM_INS; i++)
		{
			int control_rate_inlet = self->control_rate_inlets[i];
			
			//if audio rate or inlet is used for buffers, break!
			if(control_rate_inlet < 0)
				break;
			
			double  control_rate_inlet_val = self->input_vals[control_rate_inlet];
			double* control_rate_array     = self->control_rate_arrays[control_rate_inlet];
			
			if(control_rate_array)
			{
				//fill values
				for(int y = 0; y < sampleframes; y++)
					control_rate_array[y] = control_rate_inlet_val;

				//Switch pointers in ins**
				ins[control_rate_inlet] = control_rate_array;
			}
		}
	}

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
	//Special case, if there is a change in samplerate or bufsize, 
	//and object has already been allocated and initialized, 
	//get rid of previous object, allocate new and re-init.
	if(((max_samplerate != samplerate) || max_bufsize != maxvectorsize) && self->omni_ugen && self->omni_ugen_is_init)
	{
		//Free, then re-alloc
		Omni_UGenFree(self->omni_ugen);
		self->omni_ugen = Omni_UGenAlloc();

		//Change samplerate and bufsize HERE, so they are also available in omni init via the get_samplerate/get_bufsize templates
		max_samplerate = samplerate;
		max_bufsize    = maxvectorsize;

		//re-init the ugen
		Omni_UGenInit64(self->omni_ugen, self->args, (int)maxvectorsize, samplerate, (void*)self);
	}

	//Standard case, don't re-init object everytime dsp chain is recompiled, but just one time:
	//Data and structs need only to be allocated once!
	if(self->omni_ugen && !(self->omni_ugen_is_init))
	{
		//Change samplerate and bufsize HERE, so they are also available in omni init via the get_samplerate/get_bufsize templates
		max_samplerate = samplerate;
		max_bufsize    = maxvectorsize;
		
		//init ugen
		Omni_UGenInit64(self->omni_ugen, self->args, (int)maxvectorsize, samplerate, (void*)self);
		self->omni_ugen_is_init = true;
	}

	//Reset input rates first
	for(int i = 0; i < NUM_INS; i++)
		self->control_rate_inlets[i] = -1;

	//Look for control rate inlets
	int control_rate_inlets_increment = 0;
	for(int i = 0; i < NUM_INS; i++)
	{
		//If it's not audio rate
		bool control_rate_inlet = !(bool(count[i]));
		
		void* is_valid_buffer_ref_ptr = (void*)self->buffer_refs_array[i];
		
		//Add if it's control rate and it's not used for buffer handling
		if(control_rate_inlet && !(is_valid_buffer_ref_ptr))
		{
			self->control_rate_inlets[control_rate_inlets_increment] = i;
			control_rate_inlets_increment++;

			//Allocate array if necessary
			double* control_rate_array = self->control_rate_arrays[i];
			if(!control_rate_array)
				self->control_rate_arrays[i] = (double*)malloc(maxvectorsize * sizeof(double));
		}
	}

	//Add dsp64 method
	object_method_direct(void, (t_object*, t_object*, t_perfroutine64, long, void*),
						 dsp64, gensym("dsp_add64"), (t_object*)self, (t_perfroutine64)omniobj_perform64, 0, NULL);
}
"""