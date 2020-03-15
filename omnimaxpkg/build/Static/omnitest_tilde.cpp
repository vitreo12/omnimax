//C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\MSBuild.exe
//.\MSBuild.exe /p:Configuration=Release /p:Platform=x64 "C:\Users\frank\Documents\Max 7\Library\max-sdk-7.3.3\source\audio\omnitest~\omnitest~.vcxproj"


//cmake -G "MinGW Makefiles" ..
//mingw32-make

#include "c74_msp.h"
#include "omni.h"

using namespace c74::max;

#define post(...)	object_post(NULL, __VA_ARGS__)

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

} t_omnitest;

//Template functions
void* omnitest_new(t_symbol *s, long argc, t_atom *argv);
void  omnitest_free(t_omnitest *x);
void  omnitest_assist(t_omnitest* self, void* unused, t_assist_function io, long index, char* string_dest);
void  omnitest_perform64(t_omnitest* x, t_object* dsp64, double** ins, long numins, double** outs, long numouts, long sampleframes, long flags, void* userparam);
void  omnitest_dsp64(t_omnitest* self, t_object* dsp64, short *count, double samplerate, long maxvectorsize, long flags);

void ext_main(void *r)
{
	this_class = class_new("libomnitest~", (method)omnitest_new, (method)omnitest_free, sizeof(t_omnitest), NULL, A_GIMME, 0);
	
	class_addmethod(this_class, (method)omnitest_dsp64,		"dsp64",	A_CANT, 0);
	class_addmethod(this_class, (method)omnitest_assist,    "assist",	A_CANT, 0);

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
	t_omnitest *self = (t_omnitest *)object_alloc(this_class);

	//Inlets
	dsp_setup((t_pxobject *)self, 1);

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

void omnitest_free(t_omnitest *self)
{
	if(self->omni_ugen)
		Omni_UGenFree(self->omni_ugen);

	dsp_free((t_pxobject *)self);
}

void omnitest_assist(t_omnitest* self, void* unused, t_assist_function io, long index, char* string_dest)
{
	//Inlets assist
	if (io == ASSIST_INLET) 
	{
		switch (index) 
		{
			case 0:
				strncpy(string_dest, "(signal/symbol) in1", ASSIST_STRING_MAXSIZE);
				break;
		}
	}

	//Outlets assist
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
	if (self->omni_ugen)
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
	post("Max samplerate: %f", samplerate);
	post("Max vector size: %d", (int)maxvectorsize);

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
		Omni_UGenInit(self->omni_ugen, nullptr, (int)maxvectorsize, samplerate);
	}

	//Standard case, don't re-init object everytime dsp chain is recompiled, but just one time:
	//Data and structs need only to be allocated once!
	if(self->omni_ugen && !(self->omni_ugen_is_init))
	{
		//Change samplerate and bufsize HERE, so they are also available in omni init via the get_samplerate/get_bufsize templates
		max_samplerate = samplerate;
		max_bufsize    = maxvectorsize;
		
		//init ugen
		Omni_UGenInit(self->omni_ugen, nullptr, (int)maxvectorsize, samplerate);
		self->omni_ugen_is_init = true;
	}

	//Add dsp64 method
	object_method_direct(void, (t_object*, t_object*, t_perfroutine64, long, void*),
						 dsp64, gensym("dsp_add64"), (t_object*)self, (t_perfroutine64)omnitest_perform64, 0, NULL);
}