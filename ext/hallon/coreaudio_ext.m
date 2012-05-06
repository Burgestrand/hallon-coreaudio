#import <Foundation/Foundation.h>
#import <ruby.h>

VALUE ha_cCoreAudio = Qnil;

void Init_coreaudio_ext()
{
  VALUE mHallon = rb_const_get(rb_cObject, rb_intern("Hallon"));
  ha_cCoreAudio = rb_define_class_under(mHallon, "CoreAudio", rb_cObject);
}
