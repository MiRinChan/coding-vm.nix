#!/usr/bin/env python3
"""Render one pixel through the guest DRM node without a display server."""

import ctypes as c
import os
import sys


def bind(library, name, result, *args):
    function = getattr(library, name)
    function.restype = result
    function.argtypes = args
    return function


egl, gl, gbm = (c.CDLL(path) for path in sys.argv[1:4])
ptr, integer, uint = c.c_void_p, c.c_int, c.c_uint
fd = os.open("/dev/dri/renderD128", os.O_RDWR)
device = bind(gbm, "gbm_create_device", ptr, integer)(fd)
assert device, "gbm_create_device failed"
display = bind(egl, "eglGetPlatformDisplay", ptr, uint, ptr, ptr)(
    0x31D7, device, None
)
major, minor = integer(), integer()
assert bind(egl, "eglInitialize", uint, ptr, ptr, ptr)(
    display, c.byref(major), c.byref(minor)
), "eglInitialize failed"
assert bind(egl, "eglBindAPI", uint, uint)(0x30A0), "eglBindAPI failed"
attributes = (integer * 5)(0x3040, 4, 0x3033, 0, 0x3038)
config, count = ptr(), integer()
assert bind(egl, "eglChooseConfig", uint, ptr, ptr, ptr, integer, ptr)(
    display, attributes, c.byref(config), 1, c.byref(count)
) and count.value, "No GLES2 EGL configuration"
context_attributes = (integer * 3)(0x3098, 2, 0x3038)
context = bind(egl, "eglCreateContext", ptr, ptr, ptr, ptr, ptr)(
    display, config, None, context_attributes
)
assert context, "eglCreateContext failed"
assert bind(egl, "eglMakeCurrent", uint, ptr, ptr, ptr, ptr)(
    display, None, None, context
), "Surfaceless eglMakeCurrent failed"
renderer = bind(gl, "glGetString", c.c_char_p, uint)(0x1F01).decode()
print(f"EGL {major.value}.{minor.value}, renderer: {renderer}")
assert "virgl" in renderer.lower(), f"Expected VirGL hardware rendering: {renderer}"

texture, framebuffer = uint(), uint()
bind(gl, "glGenTextures", None, integer, ptr)(1, c.byref(texture))
bind(gl, "glBindTexture", None, uint, uint)(0x0DE1, texture.value)
bind(gl, "glTexParameteri", None, uint, uint, integer)(0x0DE1, 0x2801, 0x2600)
bind(gl, "glTexImage2D", None, uint, integer, integer, integer, integer, integer, uint, uint, ptr)(
    0x0DE1, 0, 0x1908, 1, 1, 0, 0x1908, 0x1401, None
)
bind(gl, "glGenFramebuffers", None, integer, ptr)(1, c.byref(framebuffer))
bind(gl, "glBindFramebuffer", None, uint, uint)(0x8D40, framebuffer.value)
bind(gl, "glFramebufferTexture2D", None, uint, uint, uint, uint, integer)(
    0x8D40, 0x8CE0, 0x0DE1, texture.value, 0
)
assert bind(gl, "glCheckFramebufferStatus", uint, uint)(0x8D40) == 0x8CD5
bind(gl, "glClearColor", None, c.c_float, c.c_float, c.c_float, c.c_float)(0, 1, 0, 1)
bind(gl, "glClear", None, uint)(0x4000)
pixel = (c.c_ubyte * 4)()
bind(gl, "glReadPixels", None, integer, integer, integer, integer, uint, uint, ptr)(
    0, 0, 1, 1, 0x1908, 0x1401, pixel
)
assert list(pixel) == [0, 255, 0, 255], list(pixel)
assert bind(gl, "glGetError", uint)() == 0
print("PASS: headless VirGL framebuffer render and pixel readback")
bind(egl, "eglMakeCurrent", uint, ptr, ptr, ptr, ptr)(display, None, None, None)
bind(egl, "eglDestroyContext", uint, ptr, ptr)(display, context)
bind(egl, "eglTerminate", uint, ptr)(display)
bind(gbm, "gbm_device_destroy", None, ptr)(device)
os.close(fd)
