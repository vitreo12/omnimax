//C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\MSBuild.exe
//.\MSBuild.exe /p:Configuration=Release /p:Platform=x64 "C:\Users\frank\Documents\Max 7\Library\max-sdk-7.3.3\source\audio\omnitest~\omnitest~.vcxproj"

#include "c74_msp.h"

using namespace c74::max;

#define post(...)	object_post(NULL, __VA_ARGS__)

static t_class* this_class = nullptr;

//Should they be atomic?
static double max_samplerate = 0.0;
static long   max_bufsize    = 0;

//Initialization functions. Wrapped in C since the Omni lib is exported with C named libraries
extern "C"
{
	//Initialization function prototypes
    typedef void*  alloc_func_t(size_t inSize);
    typedef void*  realloc_func_t(void *inPtr, size_t inSize);
    typedef void   free_func_t(void *inPtr);
    typedef void   print_func_t(const char* formatString, ...);
    typedef double get_samplerate_func_t();
    typedef int    get_bufsize_func_t();

    //Initialization function
    extern  void  OmniInitGlobal(alloc_func_t* alloc_func, realloc_func_t* realloc_func, free_func_t* free_func, print_func_t* print_func, get_samplerate_func_t* get_samplerate_func, get_bufsize_func_t* get_bufsize_func);

    //Omni module functions
    extern void* OmniAllocObj();
	extern void  OmniInitObj(void* obj, float** ins_SC, int bufsize_in, double samplerate_in);
    extern void  OmniDestructor(void* obj_void);
    extern void  OmniPerform(void* ugen_void, long buf_size, double** ins_SC, double** outs_SC);
}

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
	return int(max_bufsize);
}

//Max struct
typedef struct _omnitest {
	t_pxobject w_obj;
	
	void* omni_obj;
	bool  omni_obj_is_init;

} t_omnitest;

//Template functions
void *omnitest_new(t_symbol *s, long argc, t_atom *argv);
void omnitest_free(t_omnitest *x);
void omnitest_assist(t_omnitest* self, void* unused, t_assist_function io, long index, char* string_dest);
void omnitest_perform64(t_omnitest* x, t_object* dsp64, double** ins, long numins, double** outs, long numouts, long sampleframes, long flags, void* userparam);
void omnitest_dsp64(t_omnitest* self, t_object* dsp64, short *count, double samplerate, long maxvectorsize, long flags);

void ext_main(void *r)
{
	this_class = class_new("libomnitest~", (method)omnitest_new, (method)omnitest_free, sizeof(t_omnitest), NULL, A_GIMME, 0);
	
	class_addmethod(this_class, (method)omnitest_dsp64,		"dsp64",	A_CANT, 0);
	class_addmethod(this_class, (method)omnitest_assist,    "assist",	A_CANT, 0);

	//Init all function pointers
	OmniInitGlobal(
		(alloc_func_t*)malloc, 
		(realloc_func_t*)realloc, 
		(free_func_t*)free, 
		(print_func_t*)maxPrint, 
		(get_samplerate_func_t*)get_maxSamplerate,
		(get_bufsize_func_t*)get_maxBufSize
	);
	
	class_dspinit(this_class);
	class_register(CLASS_BOX, this_class);
}

//New method looking at args
void *omnitest_new(t_symbol *s, long argc, t_atom *argv)
{
	t_omnitest *self = (t_omnitest *)object_alloc(this_class);

	//Number of audio inlets
	dsp_setup((t_pxobject *)self, 1);

	//Allocate Omni object. Inputs can't be passed here, but arguments and attributes may be...
	if(!self->omni_obj)
	{
		self->omni_obj = OmniAllocObj();
		self->omni_obj_is_init = false;
	}

	//new outlet
	outlet_new((t_object *)self, "signal");		

	return self;
}

void omnitest_free(t_omnitest *self)
{
	if(self->omni_obj)
		OmniDestructor(self->omni_obj);

	dsp_free((t_pxobject *)self);
}

void omnitest_assist(t_omnitest* self, void* unused, t_assist_function io, long index, char* string_dest)
{
	//INLETS
	if (io == ASSIST_INLET) 
	{
		switch (index) 
		{
			case 0:
				strncpy(string_dest, "(signal/symbol) in1", ASSIST_STRING_MAXSIZE);
				break;
		}
	}

	//OUTLETS
	else if (io == ASSIST_OUTLET)
	{
		switch (index) 
		{
			case 0:
				strncpy(string_dest, "(signal) out1", ASSIST_STRING_MAXSIZE);
				break;
		}
	}
}

void omnitest_perform64(t_omnitest* self, t_object* dsp64, double** ins, long numins, double** outs, long numouts, long sampleframes, long flags, void* userparam)
{
	if (self->omni_obj)
		OmniPerform(self->omni_obj, sampleframes, ins, outs);
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
	post("Max samplerate: %f", samplerate);
	post("Max vector size: %lu", maxvectorsize);

	//Special case, if there is a change in samplerate or bufsize, 
	//and object has already been allocated and initialized, 
	//get rid of previous object, allocate new and re-init.
	if(((max_samplerate != samplerate) || max_bufsize != maxvectorsize) && self->omni_obj && self->omni_obj_is_init)
	{
		//Re-initialize everything omni related
		OmniDestructor(self->omni_obj);
		self->omni_obj = OmniAllocObj();
		OmniInitObj(self->omni_obj, nullptr, maxvectorsize, samplerate);
	}

	//Standard case, don't re-init object everytime dsp chain is recompiled, but just one time:
	//Data and structs need only to be allocated once!
	if(self->omni_obj && !(self->omni_obj_is_init))
	{
		OmniInitObj(self->omni_obj, nullptr, maxvectorsize, samplerate);
		self->omni_obj_is_init = true;
	}

	//Change samplerate and bufsize (so they are available in omni via the get_samplerate/get_bufsize templates)
	max_samplerate = samplerate;
	max_bufsize    = maxvectorsize;

	//Add dsp64 method
	object_method_direct(void, (t_object*, t_object*, t_perfroutine64, long, void*),
						 dsp64, gensym("dsp_add64"), (t_object*)self, (t_perfroutine64)omnitest_perform64, 0, NULL);
}