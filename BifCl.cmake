
# A macro to define a command that uses the BIF compiler to produce C++
# segments and Bro language declarations from a .bif file. The outputs
# are returned in BIF_OUTPUT_{CC,H,BRO}. By default, it runs bifcl in
# alternative mode (-a; suitable for standalone compilation). If
# an additional parameter "standard" is given, it runs it in standard mode
# for inclusion in NetVar.*. If an additional parameter "plugin" is given,
# it runs it in plugin mode (-p). In the latter case, one more argument
# is required with the plugin's name.
#
# The macro also creates a target that can be used to define depencencies on
# the generated files. The name of the target depends on the mode and includes
# a normalized path to the input bif to make it unique. The target is added
# automatically to bro_ALL_GENERATED_OUTPUTS.
macro(bif_target bifInput)
    set(target "")
    get_filename_component(bifInputBasename "${bifInput}" NAME)

    if ( "${ARGV1}" STREQUAL "standard" )
        set(bifcl_args "")
        set(target "bif-std-${CMAKE_CURRENT_BINARY_DIR}/${bifInputBasename}")
        set(bifOutputs
            ${CMAKE_CURRENT_BINARY_DIR}/${bifInputBasename}.func_def
            ${CMAKE_CURRENT_BINARY_DIR}/${bifInputBasename}.func_h
            ${CMAKE_CURRENT_BINARY_DIR}/${bifInputBasename}.func_init
            ${CMAKE_CURRENT_BINARY_DIR}/${bifInputBasename}.netvar_def
            ${CMAKE_CURRENT_BINARY_DIR}/${bifInputBasename}.netvar_h
            ${CMAKE_CURRENT_BINARY_DIR}/${bifInputBasename}.netvar_init)
    	set(BIF_OUTPUT_CC  ${bifInputBasename}.func_def
                           ${bifInputBasename}.func_init
                           ${bifInputBasename}.netvar_def
                           ${bifInputBasename}.netvar_init)
        set(BIF_OUTPUT_H   ${bifInputBasename}.func_h
                           ${bifInputBasename}.netvar_h)
	    set(BIF_OUTPUT_BRO ${CMAKE_BINARY_DIR}/scripts/base/bif/${bifInputBasename}.bro)

    elseif ( "${ARGV1}" STREQUAL "plugin" )
        set(plugin_name ${ARGV2})
        set(plugin_name_canon ${ARGV3})
        set(plugin_is_static ${ARGV4})
        set(target "bif-plugin-${plugin_name_canon}-${bifInputBasename}")
        set(bifcl_args "-p;${plugin_name}")
        set(bifOutputs
            ${bifInputBasename}.h
            ${bifInputBasename}.cc
            ${bifInputBasename}.init.cc
            ${bifInputBasename}.register.cc)

        if ( plugin_is_static )
        	set(BIF_OUTPUT_CC  ${bifInputBasename}.cc
                               ${bifInputBasename}.init.cc)
            set(bro_REGISTER_BIFS ${bro_REGISTER_BIFS} ${CMAKE_CURRENT_BINARY_DIR}/${bifInputBasename} CACHE INTERNAL "BIFs for automatic registering" FORCE) # Propagate to top-level.
        else ()
        	set(BIF_OUTPUT_CC  ${bifInputBasename}.cc
                               ${bifInputBasename}.init.cc
                               ${bifInputBasename}.register.cc)
        endif()

        set(BIF_OUTPUT_H   ${bifInputBasename}.h)

        if ( NOT BRO_PLUGIN_BUILD_DYNAMIC )
        	set(BIF_OUTPUT_BRO ${CMAKE_BINARY_DIR}/scripts/base/bif/plugins/${plugin_name_canon}.${bifInputBasename}.bro)
        else ()
        	set(BIF_OUTPUT_BRO ${BRO_PLUGIN_BIF}/${bifInputBasename}.bro)
        endif()

    else ()
        # Alternative mode. These will get compiled in automatically.
        set(bifcl_args "-s")
        set(target "bif-alt-${CMAKE_CURRENT_BINARY_DIR}/${bifInputBasename}")
        set(bifOutputs
            ${bifInputBasename}.h
            ${bifInputBasename}.cc
            ${bifInputBasename}.init.cc)
    	set(BIF_OUTPUT_CC  ${bifInputBasename}.cc)
        set(BIF_OUTPUT_H   ${bifInputBasename}.h)

        # In order be able to run bro from the build directory, the
        # generated bro script needs to be inside a directory tree
        # named the same way it will be referenced from an @load.
	    set(BIF_OUTPUT_BRO ${CMAKE_BINARY_DIR}/scripts/base/bif/${bifInputBasename}.bro)

        set(bro_AUTO_BIFS  ${bro_AUTO_BIFS} ${CMAKE_CURRENT_BINARY_DIR}/${bifInputBasename} CACHE INTERNAL "BIFs for automatic inclusion" FORCE) # Propagate to top-level.
    endif ()

    if ( BRO_PLUGIN_INTERNAL_BUILD )
       set(bifclDep "bifcl")
    endif ()

    if ( BRO_PLUGIN_INTERNAL_BUILD )
        set(BifCl_EXE "bifcl")
    else ()
        set(BifCl_EXE "${BRO_PLUGIN_BRO_BUILD}/src/bifcl")
    endif ()

    add_custom_command(OUTPUT ${bifOutputs} ${BIF_OUTPUT_BRO}
                       COMMAND ${BifCl_EXE}
                       ARGS ${bifcl_args} ${CMAKE_CURRENT_SOURCE_DIR}/${bifInput} || (rm -f ${bifOutputs} && exit 1)
                       COMMAND "${CMAKE_COMMAND}"
                       ARGS -E copy ${bifInputBasename}.bro ${BIF_OUTPUT_BRO}
                       COMMAND "${CMAKE_COMMAND}"
                       ARGS -E remove -f ${bifInputBasename}.bro
                       DEPENDS ${bifInput}
                       DEPENDS ${bifclDep}
                       COMMENT "[BIFCL] Processing ${bifInput}"
    )

    string(REGEX REPLACE "${CMAKE_BINARY_DIR}/src/" "" target "${target}")
    string(REGEX REPLACE "/" "-" target "${target}")
    add_custom_target(${target} DEPENDS ${BIF_OUTPUT_H} ${BIF_OUTPUT_CC})
    set_source_files_properties(${bifOutputs} PROPERTIES GENERATED 1)
    set(BIF_BUILD_TARGET ${target})

    set(bro_ALL_GENERATED_OUTPUTS ${bro_ALL_GENERATED_OUTPUTS} ${target} CACHE INTERNAL "automatically generated files" FORCE) # Propagate to top-level.
endmacro(bif_target)

# A macro to create a __load__.bro file for all *.bif.bro files found
# in a given directory. It creates a corresponding target to trigger
# the generation.
function(bro_bif_create_loader target dstdir)
     file(MAKE_DIRECTORY ${dstdir})
     add_custom_target(${target}
			COMMAND "sh" "-c" "find . -name \\*\\.bif\\.bro | sort -f | sed 's#\\(.*\\).bro#@load \\1#g' >__load__.bro"
			WORKING_DIRECTORY ${dstdir}
			VERBATIM
			)
     add_dependencies(${target} generate_outputs)
endfunction()

# A macro to create joint include files for compiling in all the
# autogenerated bif code.
function(bro_bif_create_includes target dstdir bifinputs)
    file(MAKE_DIRECTORY ${dstdir})

    add_custom_target(${target}
        COMMAND "sh" "-c" "rm -f ${dstdir}/__all__.bif.cc.tmp"
        COMMAND "sh" "-c" "rm -f ${dstdir}/__all__.bif.init.cc.tmp"

        COMMAND for i in ${bifinputs}\; do echo \\\#include \\"\$\$i.cc\\"\; done >> ${dstdir}/__all__.bif.cc.tmp
        COMMAND for i in ${bifinputs}\; do echo \\\#include \\"\$\$i.init.cc\\"\; done >> ${dstdir}/__all__.bif.init.cc.tmp

        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${dstdir}/__all__.bif.cc.tmp" "${dstdir}/__all__.bif.cc"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${dstdir}/__all__.bif.init.cc.tmp" "${dstdir}/__all__.bif.init.cc"

        COMMAND "sh" "-c" "rm -f ${dstdir}/__all__.bif.cc.tmp"
        COMMAND "sh" "-c" "rm -f ${dstdir}/__all__.bif.init.cc.tmp"

	    WORKING_DIRECTORY ${dstdir}
		)

    set(clean_files ${dstdir}/__all__.bif.cc ${dstdir}/__all__.bif.init.cc)
    set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES "${clean_files}")
endfunction()

function(bro_bif_create_register target dstdir bifinputs)
    file(MAKE_DIRECTORY ${dstdir})

    add_custom_target(${target}
        COMMAND "sh" "-c" "rm -f ${dstdir}/__all__.bif.register.cc.tmp"
        COMMAND for i in ${bifinputs}\; do echo \\\#include \\"\$\$i.register.cc\\"\; done >> ${dstdir}/__all__.bif.register.cc.tmp

        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${dstdir}/__all__.bif.register.cc.tmp" "${dstdir}/__all__.bif.register.cc"

        COMMAND "sh" "-c" "rm -f ${dstdir}/__all__.bif.register.cc.tmp"

	    WORKING_DIRECTORY ${dstdir}
		)

    set(clean_files ${dstdir}/__all__.bif.cc ${dstdir}/__all__.bif.register.cc)
    set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES "${clean_files}")
endfunction()
