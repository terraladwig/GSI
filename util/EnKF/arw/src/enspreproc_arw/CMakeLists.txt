cmake_minimum_required(VERSION 2.6)
  file(GLOB LOCAL_SRC ${CMAKE_CURRENT_SOURCE_DIR}/*.f90)
  set_source_files_properties( ${LOCAL_SRC} PROPERTIES COMPILE_FLAGS ${GSI_Fortran_FLAGS} )
  include_directories( ${PROJECT_BINARY_DIR}/include ${NETCDF_INCLUDE_DIRS}  ${MPI_Fortran_INCLUDE_PATH} )

  add_executable(enspreprocess_arw.x ${LOCAL_SRC} )
  set_target_properties( enspreprocess_arw.x PROPERTIES COMPILE_FLAGS ${GSI_Fortran_FLAGS} )
  target_link_libraries( enspreprocess_arw.x ${GSISHAREDLIB} ${GSILIB} ${GSISHAREDLIB} ${WRF_LIBRARIES} 
         ${NETCDF_Fortran_LIBRARIES} ${NETCDF_C_LIBRARIES} ${MPI_Fortran_LIBRARIES} 
         ${LAPACK_LIBRARIES} -L./ ${EXTRA_LINKER_FLAGS} ${CORE_LIBRARIES} ${CORE_BUILT}
         ${GSI_LDFLAGS} ${NCDIAG_LIBRARIES} ${wrflib} ${FV3GFS_NCIO_LIBRARIES} )
  add_dependencies(enspreprocess_arw.x ${GSILIB})

