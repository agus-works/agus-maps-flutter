// Copyright (c) Agus Maps
//
// iOS uses the native CoMaps localization implementation, so we only expose
// the C API required by the Flutter plugin. This avoids duplicate symbols
// from the shared localization translation unit.

#import <Foundation/Foundation.h>

#include <string>

extern "C" {

__attribute__((visibility("default")))
void agus_localization_set_locale(const char* localeTag)
{
	(void)localeTag;
	// No-op on iOS: localization follows the current system locale.
}

__attribute__((visibility("default")))
const char* agus_localization_get_locale()
{
	@autoreleasepool {
		NSString* localeId = [[NSLocale currentLocale] localeIdentifier];
		static thread_local std::string s_locale;
		if (localeId == nil) {
			s_locale.clear();
		} else {
			s_locale = [localeId UTF8String];
		}
		return s_locale.empty() ? nullptr : s_locale.c_str();
	}
}

}  // extern "C"
