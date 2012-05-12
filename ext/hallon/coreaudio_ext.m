#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioQueue.h>
#import <ruby.h>

extern void *rb_thread_call_with_gvl(void *(*func)(void *), void *data1);

//
// Globals
//
VALUE ha_cCoreAudio = Qnil;

ID ha_key_channels;
ID ha_key_rate;
ID ha_key_type;

//
// Preprocessor stuff
//

#define NUM_BUFFERS 3
#define BUFFER_SIZE 2000

#define FORMAT_CHANNELS(format_hash) FIX2INT(HASH_AREF((format_hash), ha_key_channels))
#define FORMAT_RATE(format_hash) FIX2INT(HASH_AREF((format_hash), ha_key_rate))

#define STR2SYM(x) ID2SYM(rb_intern((x)))
#define HASH_AREF(hash, key) rb_funcall((hash), rb_intern("[]"), 1, (key))

//
// Types
//
struct ha_state_t
{
  AudioQueueRef queue;
};

struct ha_callback_t
{
  void *userData;
  AudioQueueRef inAq;
  AudioQueueBufferRef inBuffer;
};

struct ha_userdata_t
{
  VALUE callback_proc;
  VALUE format_hash;
};

struct ha_non_gvl_t
{
  CFRunLoopRef runLoop;
  BOOL shouldExit;
};

typedef struct ha_userdata_t ha_userdata_t;
typedef struct ha_non_gvl_t ha_non_gvl_t;
typedef struct ha_callback_t ha_callback_t;
typedef struct ha_state_t ha_state_t;

//
// Audio queue callback
//

//
// Audio queue
//
static AudioStreamBasicDescription *construct_format(VALUE format_hash)
{
  AudioStreamBasicDescription *format = ALLOC(AudioStreamBasicDescription);

  format->mSampleRate  = FORMAT_RATE(format_hash);
  format->mChannelsPerFrame = FORMAT_CHANNELS(format_hash);
  format->mFormatID    = kAudioFormatLinearPCM;
  format->mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagsNativeEndian;
  format->mFramesPerPacket = 1;
  format->mBitsPerChannel = 8 * sizeof(short);
  format->mBytesPerFrame  = format->mChannelsPerFrame * (int) sizeof(short);
  format->mBytesPerPacket = format->mBytesPerFrame * format->mFramesPerPacket;
  format->mReserved = 0;
}

//
// Ruby
//

static void ha_free(ha_state_t *state)
{
  xfree(state);
}

static VALUE ha_alloc(VALUE klass)
{
  ha_state_t *state;
  return Data_Make_Struct(klass, ha_state_t, NULL, ha_free, state);
}

static VALUE ha_initialize(VALUE ruby_self)
{
}

//
// Audio driver interface
//

static VALUE ha_pause(VALUE ruby_self)
{
  ha_state_t *state;
  Data_Get_Struct(ruby_self, ha_state_t, state);
  AudioQueuePause(state->queue);
  return ruby_self;
}

static VALUE ha_stop(VALUE ruby_self)
{
  ha_state_t *state;
  Data_Get_Struct(ruby_self, ha_state_t, state);
  AudioQueueStop(state->queue, true);
  return ruby_self;
}

static VALUE ha_play(VALUE ruby_self)
{
  ha_state_t *state;
  Data_Get_Struct(ruby_self, ha_state_t, state);
  AudioQueueStart(state->queue, true);
  return ruby_self;
}

static void audio_callback(void *userData, AudioQueueRef Aq, AudioQueueBufferRef outBuffer)
{
  ha_userdata_t *real_user_data = (ha_userdata_t*)userData;

  VALUE callback_proc = real_user_data->callback_proc;
  VALUE format_hash   = real_user_data->format_hash;

  int num_frames      = FORMAT_RATE(format_hash);
  int num_channels    = FORMAT_CHANNELS(format_hash);

  short *audio_data = (short *) outBuffer->mAudioData;
  int requested_samples = outBuffer->mAudioDataBytesCapacity / num_channels;

  // if ruby blocks here, this segfaults (like, if the audio queue is empty)
  VALUE frames = rb_funcall(callback_proc, rb_intern("call"), 1, INT2FIX(requested_samples));

  if ( ! RTEST(frames))
  {
    CFRunLoopStop(CFRunLoopGetCurrent()); // format changed
    return;
  }

  int num_received_samples = ((int) RARRAY_LEN(frames)) * num_channels;

  outBuffer->mAudioDataByteSize = num_received_samples;

  VALUE frame, sample;
  int i, rb_i, rb_j;
  for (i = 0; i < num_received_samples; ++i)
  {
    rb_i = i / num_channels; // integer division
    rb_j = i % num_channels;

    frame  = RARRAY_PTR(frames)[rb_i];
    sample = RARRAY_PTR(frame)[rb_j];

    audio_data[i] = (short) FIX2LONG(sample);
  }

  AudioQueueEnqueueBuffer(Aq, outBuffer, 0, NULL);
}

static void *gvl_audio_callback_caller(void *_callback)
{
  ha_callback_t *callback = (ha_callback_t *)_callback;
  audio_callback(callback->userData, callback->inAq, callback->inBuffer);
}

static void non_gvl_audio_callback(void *userData, AudioQueueRef inAq, AudioQueueBufferRef inBuffer)
{
  ha_callback_t callback = { .userData = userData, .inAq = inAq, .inBuffer = inBuffer };
  rb_thread_call_with_gvl(gvl_audio_callback_caller, &callback);
}

static VALUE non_gvl_CFRunLoopRun(void *data)
{
  CFRunLoopRun();
}

static void non_gvl_CFRunLoopStop(void *_data)
{
  ha_non_gvl_t *data = (ha_non_gvl_t *)_data;
  CFRunLoopStop(data->runLoop);
  data->shouldExit = YES;
}

static VALUE ha_stream(VALUE ruby_self)
{
  ha_state_t *state;
  NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
  ha_non_gvl_t loopData = { .runLoop = [runLoop getCFRunLoop], .shouldExit = NO };
  VALUE callback_proc = rb_block_proc();
  int i = 0;

  Data_Get_Struct(ruby_self, ha_state_t, state);

  while (loopData.shouldExit == NO)
  {
    VALUE format_hash = rb_funcall(ruby_self, rb_intern("format"), 0);
    ha_userdata_t userdata = { .callback_proc = callback_proc, .format_hash = format_hash };

    AudioStreamBasicDescription *format = construct_format(format_hash);
    OSStatus error = AudioQueueNewOutput(format, non_gvl_audio_callback, (void *)&userdata, CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &state->queue);

    if (error != noErr)
    {
      rb_raise(rb_eRuntimeError, "%s", GetMacOSStatusErrorString(error));
    }

    AudioQueueBufferRef buffers[NUM_BUFFERS];

    for (i = 0; i < NUM_BUFFERS; i++)
    {
      AudioQueueAllocateBuffer(state->queue, (UInt32) format->mSampleRate, &buffers[i]);
      buffers[i]->mAudioDataByteSize = (UInt32) format->mSampleRate;
      audio_callback((void *)&userdata, state->queue, buffers[i]);
    }

    xfree(format);

    rb_thread_blocking_region(non_gvl_CFRunLoopRun, NULL, non_gvl_CFRunLoopStop, &loopData);

    AudioQueueDispose(state->queue, true);
  }

  return ruby_self;
}

void Init_coreaudio_ext()
{
  VALUE mHallon = rb_const_get(rb_cObject, rb_intern("Hallon"));
  ha_cCoreAudio = rb_define_class_under(mHallon, "CoreAudio", rb_cObject);

  ha_key_channels = STR2SYM("channels");
  ha_key_rate     = STR2SYM("rate");
  ha_key_type     = STR2SYM("type");

  rb_define_alloc_func(ha_cCoreAudio, ha_alloc);
  rb_define_method(ha_cCoreAudio, "initialize", ha_initialize, 0);
  rb_define_method(ha_cCoreAudio, "pause", ha_pause, 0);
  rb_define_method(ha_cCoreAudio, "stop", ha_stop, 0);
  rb_define_method(ha_cCoreAudio, "play", ha_play, 0);
  rb_define_method(ha_cCoreAudio, "stream", ha_stream, 0);
}
