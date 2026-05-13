include_guard(GLOBAL)

macro(agus_enable_msvc_parallel_builds)
  if(MSVC)
    get_property(_agus_msvc_parallel_enabled GLOBAL PROPERTY AGUS_MSVC_PARALLEL_ENABLED)
    if(NOT _agus_msvc_parallel_enabled)
      include(ProcessorCount)
      ProcessorCount(_agus_msvc_processor_count)
      if(NOT _agus_msvc_processor_count OR _agus_msvc_processor_count LESS 1)
        set(_agus_msvc_processor_count 1)
      endif()

      if(NOT DEFINED AGUS_MSVC_PARALLEL_JOBS)
        if(DEFINED ENV{AGUS_MSVC_PARALLEL_JOBS} AND NOT "$ENV{AGUS_MSVC_PARALLEL_JOBS}" STREQUAL "")
          set(AGUS_MSVC_PARALLEL_JOBS "$ENV{AGUS_MSVC_PARALLEL_JOBS}" CACHE STRING
              "MSVC compiler/linker worker count for Agus Windows builds")
        else()
          set(AGUS_MSVC_PARALLEL_JOBS "${_agus_msvc_processor_count}" CACHE STRING
              "MSVC compiler/linker worker count for Agus Windows builds")
        endif()
      endif()

      set(_agus_msvc_jobs_valid TRUE)
      if(NOT "${AGUS_MSVC_PARALLEL_JOBS}" MATCHES "^[0-9]+$")
        set(_agus_msvc_jobs_valid FALSE)
      elseif(AGUS_MSVC_PARALLEL_JOBS LESS 1)
        set(_agus_msvc_jobs_valid FALSE)
      endif()

      if(NOT _agus_msvc_jobs_valid)
        message(WARNING
            "Invalid AGUS_MSVC_PARALLEL_JOBS='${AGUS_MSVC_PARALLEL_JOBS}', using ${_agus_msvc_processor_count}")
        set(AGUS_MSVC_PARALLEL_JOBS "${_agus_msvc_processor_count}" CACHE STRING
            "MSVC compiler/linker worker count for Agus Windows builds" FORCE)
      endif()

      add_compile_options(
        "$<$<COMPILE_LANGUAGE:C>:/MP${AGUS_MSVC_PARALLEL_JOBS}>"
        "$<$<COMPILE_LANGUAGE:C>:/FS>"
        "$<$<COMPILE_LANGUAGE:CXX>:/MP${AGUS_MSVC_PARALLEL_JOBS}>"
        "$<$<COMPILE_LANGUAGE:CXX>:/FS>"
      )
      add_link_options(
        "$<$<CONFIG:Release>:/CGTHREADS:${AGUS_MSVC_PARALLEL_JOBS}>"
        "$<$<CONFIG:Profile>:/CGTHREADS:${AGUS_MSVC_PARALLEL_JOBS}>"
      )

      list(APPEND CMAKE_VS_GLOBALS
        "UseMultiToolTask=true"
        "EnforceProcessCountAcrossBuilds=true"
      )

      set_property(GLOBAL PROPERTY AGUS_MSVC_PARALLEL_ENABLED TRUE)
      message(STATUS
          "Agus MSVC parallel build enabled: /MP${AGUS_MSVC_PARALLEL_JOBS}, /FS, "
          "/CGTHREADS:${AGUS_MSVC_PARALLEL_JOBS}")
    endif()
  endif()
endmacro()
