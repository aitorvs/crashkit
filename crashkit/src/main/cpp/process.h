#pragma once
#include <string>
#include <jni.h>

// It uses /proc/self/cmdline.
std::string get_process_name();
