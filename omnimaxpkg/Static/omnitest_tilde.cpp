//C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\MSBuild.exe
//.\MSBuild.exe /p:Configuration=Release /p:Platform=x64 "C:\Users\frank\Documents\Max 7\Library\max-sdk-7.3.3\source\audio\omnitest~\omnitest~.vcxproj"

//omni .\OmniSaw.omni -b:64 -u:false -l:static -i:omnimax_lang
//mkdir build
//cd build
//cmake -G "MinGW Makefiles" ..
//mingw32-make

#include <stdio.h>
#include "c74_msp.h"
#include "omni.h"

using namespace c74::max;

#define post(...)	object_post(NULL, __VA_ARGS__)

#define MAXIMUM_BUFFER_NAMES_LEN 100

static t_class* this_class = nullptr;

//Should they be atomic?
static double max_samplerate = 0.0;
static long   max_bufsize    = 0;

//print
void maxPrint(const char* formatString, ...)
{
	post(formatString);
}

//samplerate
double get_maxSamplerate()
{
	return max_samplerate;
}

//bufsize
int get_maxBufSize()
{
	return (int)max_bufsize;
}

//Max struct
typedef struct _omnitest {
	t_pxobject w_obj;
	
	void* omni_ugen;
	bool  omni_ugen_is_init;

	//These are used to pass arguments to the init function (in1, in2, etc...)
	int num_ins;
	double** args;

	//Array of possible buffers and array of their names (used to parse the notify callback!!)
	t_buffer_ref** buffer_refs_array;
	char** buffer_names_array;
} t_omnitest;

//omnimax_lang stuff
extern "C"
{
	//Called in init
	void* init_buffer_at_inlet(void* max_object, int inlet)
	{
		t_buffer_ref* buffer_ref = nullptr;

		if(inlet >= 0)
		{
			t_omnitest* self = (t_omnitest*)max_object;
			
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

//Template functions
void* omnitest_new(t_symbol *s, long argc, t_atom *argv);
t_max_err omnitest_notify(t_omnitest *x, t_symbol *s, t_symbol *msg, void *sender, void *data);
void  omnitest_free(t_omnitest *x);
void  omnitest_assist(t_omnitest* self, void* unused, t_assist_function io, long index, char* string_dest);
void  omnitest_perform64(t_omnitest* x, t_object* dsp64, double** ins, long numins, double** outs, long numouts, long sampleframes, long flags, void* userparam);
void  omnitest_dsp64(t_omnitest* self, t_object* dsp64, short *count, double samplerate, long maxvectorsize, long flags);

//This is used to set buffers
void  omnitest_receive_message_any_inlet(t_omnitest* self, t_symbol* s, long argc, t_atom* argv);

void ext_main(void *r)
{
	this_class = class_new("libomnitest~", (method)omnitest_new, (method)omnitest_free, sizeof(t_omnitest), NULL, A_GIMME, 0);
	
	class_addmethod(this_class, (method)omnitest_dsp64,	 "dsp64",  A_CANT, 0);
	class_addmethod(this_class, (method)omnitest_assist, "assist", A_CANT, 0);
	class_addmethod(this_class, (method)omnitest_notify, "notify", A_CANT, 0);

	//Message to any inlet
	class_addmethod(this_class, (method)omnitest_receive_message_any_inlet, "anything", A_GIMME, 0);

	//Init all function pointers
	Omni_InitGlobal(
		(omni_alloc_func_t*)malloc, 
		(omni_realloc_func_t*)realloc, 
		(omni_free_func_t*)free, 
		(omni_print_func_t*)maxPrint, 
		(omni_get_samplerate_func_t*)get_maxSamplerate,
		(omni_get_bufsize_func_t*)get_maxBufSize
	);
	
	class_dspinit(this_class);
	class_register(CLASS_BOX, this_class);
}

//New method looking at args
void *omnitest_new(t_symbol *s, long argc, t_atom *argv)
{
	//Alloc the object
	t_omnitest *self = (t_omnitest *)object_alloc(this_class);

	//This is set by analyzing omni's IO.txt
	int num_ins = 2;
	self->num_ins = num_ins;

	//Allocate memory for eventual buffers (this should actually just be allocated if there are buffers, this is just easier now)
	self->buffer_refs_array = (t_buffer_ref**)malloc(num_ins * sizeof(t_buffer_ref*));

	self->buffer_names_array = (char**)malloc(num_ins * sizeof(char*));

	//Allocate memory for args to passed to init
	self->args = (double**)malloc(num_ins * sizeof(double*));

	//Unpack arguments. These are then used in init as "in1" "in2" etc...
	for(int i = 0; i < num_ins; i++)
	{
		//Allocate for all arguments.. Can't be bothered doing maths here
		double* arg_ptr = (double*)malloc(sizeof(double));
		self->args[i]   = arg_ptr;

		//Initialize buf_refs to nullptr! This is essential!
		self->buffer_refs_array[i]  = nullptr;

		self->buffer_names_array[i] = nullptr;

		t_atom* arg      = (argv + i);
		short   arg_type = arg->a_type;

		//numbers are passed to init, symbols are used to initialize buffers!
		if(arg_type == A_LONG)
		{
			double arg_val = double(atom_getlong(arg));
			arg_ptr[0] = arg_val;

			//post("%f", arg_val);
		}
		else if(arg_type == A_FLOAT)
		{
			double arg_val = atom_getfloat(arg);
			arg_ptr[0] = arg_val;

			//post("%f", arg_val);
		}

		//Buffer, initialize it!
		else if(arg_type == A_SYM)
		{
			t_symbol* arg_val          = atom_getsym(arg);
			t_buffer_ref* buffer_ref   = buffer_ref_new((t_object*)self, arg_val);
			self->buffer_refs_array[i] = buffer_ref;

			self->buffer_names_array[i] = (char*)malloc(MAXIMUM_BUFFER_NAMES_LEN * sizeof(char));
			strcpy(self->buffer_names_array[i], arg_val->s_name); 
		}
	}

	//Inlets
	dsp_setup((t_pxobject *)self, num_ins);

	//Allocate omni_ugen. Inputs can't be passed here, but arguments and attributes may be...
	if(!self->omni_ugen)
	{
		self->omni_ugen = Omni_UGenAlloc();
		self->omni_ugen_is_init = false;
	}

	//Outlets
	outlet_new((t_object *)self, "signal");			

	return self;
}


t_max_err omnitest_notify(t_omnitest *x, t_symbol *s, t_symbol *msg, void *sender, void *data)
{
	
	t_symbol* buffer_name = (t_symbol *)object_method((t_object *)sender, gensym("getname"));

	post("NOTIFY: received message %s for buffer name %s", msg->s_name, buffer_name->s_name);

	for(int i = 0; i < x->num_ins; i++)
	{	
		t_buffer_ref* current_buffer_ref = x->buffer_refs_array[i];
		char* current_buffer_name = x->buffer_names_array[i];

		if(current_buffer_ref)
		{
			//this crashes
			//t_buffer_obj* current_buffer_obj = buffer_ref_getobject(current_buffer_ref);
			//t_symbol* current_buffer_name = (t_symbol *)object_method((t_object *)current_buffer_obj, gensym("getname"));

			post("buffer name: %s", buffer_name->s_name);
			post("current_buffer_name: %s", current_buffer_name);
			
			if(strcmp(buffer_name->s_name, current_buffer_name) == 0)
			{
				post("NOTIFY buffer with name %s with message %s", current_buffer_name, msg->s_name);
				return buffer_ref_notify(current_buffer_ref, s, msg, sender, data);
			}
		}
	}
	
	return 0;
}

void omnitest_free(t_omnitest *self)
{
	//Free omni ugen
	if(self->omni_ugen)
		Omni_UGenFree(self->omni_ugen);

	//Free double arguments
	if(self->args)
	{
		for(int i = 0; i < self->num_ins; i++)
		{
			double* arg_ptr = self->args[i];
			if(arg_ptr)
				free(arg_ptr);
		}

		free(self->args);
	}

	//Free buffer references
	if(self->buffer_refs_array)
	{
		for(int y = 0; y < self->num_ins; y++)
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
		for(int z = 0; z < self->num_ins; z++)
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

void omnitest_assist(t_omnitest* self, void* unused, t_assist_function io, long index, char* string_dest)
{
	if (io == ASSIST_INLET) 
	{
		switch (index) 
		{
			//Inlets assists
			case 0:
				strncpy(string_dest, "(signal/symbol) in1", ASSIST_STRING_MAXSIZE);
				break;
		}
	}


	else if (io == ASSIST_OUTLET)
	{
		switch (index) 
		{
			//Outlets assists
			case 0:
				strncpy(string_dest, "(signal) out1", ASSIST_STRING_MAXSIZE);
				break;
		}
	}
}

void set_buffer_at_inlet(t_omnitest* self, long inlet, t_symbol* name)
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
	//Initialize it here
	else
	{
		buffer_ref = buffer_ref_new((t_object*)self, name);
		self->buffer_refs_array[inlet] = buffer_ref;

		self->buffer_names_array[inlet] = (char*)malloc(MAXIMUM_BUFFER_NAMES_LEN * sizeof(char));
		strcpy(self->buffer_names_array[inlet], name->s_name); 
		
		post("Initialized buffer: %p", (void*)buffer_ref);
	}
}

void omnitest_receive_message_any_inlet_defer(t_omnitest* self, t_symbol* s, long argc, t_atom* argv)
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
			t_symbol* msg = atom_getsym(argv);
			const char* msg_str = msg->s_name;
			post("Set message at inlet %d: %s", in, msg_str);
			set_buffer_at_inlet(self, in, msg);
		}

		//"set in1 bufferName"
		else if(argc == 2)
		{
			const char* first_msg  = atom_getsym(argv)->s_name;
			const char* second_msg = atom_getsym(argv + 1)->s_name;
			//post("Set message: %s %s", first_msg, second_msg);
			post("This syntax is not supported yet!!!");
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
void omnitest_receive_message_any_inlet(t_omnitest* self, t_symbol* s, long argc, t_atom* argv)
{
	defer(self, (method)omnitest_receive_message_any_inlet_defer, s, argc, argv);
}

void omnitest_perform64(t_omnitest* self, t_object* dsp64, double** ins, long numins, double** outs, long numouts, long sampleframes, long flags, void* userparam)
{
	if (self->omni_ugen_is_init)
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

void omnitest_dsp64(t_omnitest* self, t_object* dsp64, short *count, double samplerate, long maxvectorsize, long flags) 
{
	//post("Max samplerate: %f", samplerate);
	//post("Max vector size: %d", (int)maxvectorsize);

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

	//Add dsp64 method
	object_method_direct(void, (t_object*, t_object*, t_perfroutine64, long, void*),
						 dsp64, gensym("dsp_add64"), (t_object*)self, (t_perfroutine64)omnitest_perform64, 0, NULL);
}