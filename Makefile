# Makefile for 3D EAF CFD Solver (MPI + HDF5)
FC      = mpif90
FFLAGS  = -O2 -std=f2008 -Wall -Wextra -fcheck=bounds -ffree-line-length-none -I/opt/homebrew/include
FFLAGS_DBG = -O0 -g -std=f2008 -Wall -Wextra -fcheck=bounds -fbacktrace -ffree-line-length-none -I/opt/homebrew/include
FFLAGS_OPT = -O3 -march=native -std=f2008 -ffree-line-length-none -I/opt/homebrew/include

# HDF5 libraries
HDF5_LIBS = -L/opt/homebrew/lib -lhdf5_hl_fortran -lhdf5_fortran -lhdf5 -Wl,-rpath,/opt/homebrew/lib

SRCDIR  = src
BINDIR  = bin
OBJDIR  = obj

SRCS = \
	$(SRCDIR)/mod_constants.f90 \
	$(SRCDIR)/mod_mpi_topology.f90 \
	$(SRCDIR)/mod_types_3d.f90 \
	$(SRCDIR)/mod_parallel_utils.f90 \
	$(SRCDIR)/mod_workspace.f90 \
	$(SRCDIR)/mod_face_flux.f90 \
	$(SRCDIR)/mod_audit.f90 \
	$(SRCDIR)/mod_config_3d.f90 \
	$(SRCDIR)/mod_mesh_3d.f90 \
	$(SRCDIR)/mod_solver_3d.f90 \
	$(SRCDIR)/mod_boundary_3d.f90 \
	$(SRCDIR)/mod_energy_3d.f90 \
	$(SRCDIR)/mod_properties_3d.f90 \
	$(SRCDIR)/mod_momentum_3d.f90 \
	$(SRCDIR)/mod_pressure_3d.f90 \
	$(SRCDIR)/mod_drag_ergun.f90 \
	$(SRCDIR)/mod_continuity.f90 \
	$(SRCDIR)/mod_melting_3d.f90 \
	$(SRCDIR)/mod_scrap_collapse.f90 \
	$(SRCDIR)/mod_interphase_ht.f90 \
	$(SRCDIR)/mod_solid_phase.f90 \
	$(SRCDIR)/mod_arc_cassie_mayr.f90 \
	$(SRCDIR)/mod_slag_3d.f90 \
	$(SRCDIR)/mod_electrode_3d.f90 \
	$(SRCDIR)/mod_arc_radiation_mc.f90 \
	$(SRCDIR)/mod_lorentz_3d.f90 \
	$(SRCDIR)/mod_multiphase.f90 \
	$(SRCDIR)/mod_turbulence_3d.f90 \
	$(SRCDIR)/mod_radiation_do.f90 \
	$(SRCDIR)/mod_chemistry_carbon.f90 \
	$(SRCDIR)/mod_species_transport.f90 \
	$(SRCDIR)/mod_convergence_3d.f90 \
	$(SRCDIR)/mod_input_profiles.f90 \
	$(SRCDIR)/mod_fields_3d.f90 \
	$(SRCDIR)/mod_output_hdf5.f90 \
	$(SRCDIR)/main_3d.f90

OBJS = $(patsubst $(SRCDIR)/%.f90, $(OBJDIR)/%.o, $(SRCS))
TARGET = $(BINDIR)/eaf3d_mpi

.PHONY: all clean debug opt

all: dirs $(TARGET)

debug: FFLAGS = $(FFLAGS_DBG)
debug: dirs $(TARGET)

opt: FFLAGS = $(FFLAGS_OPT)
opt: dirs $(TARGET)

dirs:
	@mkdir -p $(BINDIR) $(OBJDIR)

$(TARGET): $(OBJS)
	$(FC) $(FFLAGS) -o $@ $^ $(HDF5_LIBS)

$(OBJDIR)/%.o: $(SRCDIR)/%.f90
	$(FC) $(FFLAGS) -c -o $@ $< -J$(OBJDIR)

# Module dependencies (ORDER MATTERS!)
# mod_mpi_topology first (only needs constants)
$(OBJDIR)/mod_mpi_topology.o: $(OBJDIR)/mod_constants.o

# mod_types_3d needs mod_mpi_topology
$(OBJDIR)/mod_types_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_mpi_topology.o

$(OBJDIR)/mod_parallel_utils.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o
$(OBJDIR)/mod_audit.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_mpi_topology.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_face_flux.o
$(OBJDIR)/mod_workspace.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o
$(OBJDIR)/mod_face_flux.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o
$(OBJDIR)/mod_config_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o
$(OBJDIR)/mod_mesh_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_parallel_utils.o
$(OBJDIR)/mod_solver_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_mpi_topology.o
$(OBJDIR)/mod_boundary_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o
$(OBJDIR)/mod_energy_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_solver_3d.o $(OBJDIR)/mod_boundary_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_face_flux.o $(OBJDIR)/mod_workspace.o
$(OBJDIR)/mod_properties_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o
$(OBJDIR)/mod_momentum_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_solver_3d.o $(OBJDIR)/mod_boundary_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_face_flux.o $(OBJDIR)/mod_workspace.o
$(OBJDIR)/mod_pressure_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_solver_3d.o $(OBJDIR)/mod_boundary_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_workspace.o
$(OBJDIR)/mod_drag_ergun.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o
$(OBJDIR)/mod_continuity.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_solver_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_audit.o $(OBJDIR)/mod_face_flux.o $(OBJDIR)/mod_workspace.o
$(OBJDIR)/mod_melting_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_audit.o
$(OBJDIR)/mod_scrap_collapse.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_melting_3d.o
$(OBJDIR)/mod_interphase_ht.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_melting_3d.o
$(OBJDIR)/mod_solid_phase.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_melting_3d.o $(OBJDIR)/mod_scrap_collapse.o $(OBJDIR)/mod_interphase_ht.o
$(OBJDIR)/mod_arc_cassie_mayr.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_audit.o $(OBJDIR)/mod_melting_3d.o
$(OBJDIR)/mod_slag_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_mpi_topology.o $(OBJDIR)/mod_audit.o
$(OBJDIR)/mod_electrode_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o
$(OBJDIR)/mod_arc_radiation_mc.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_audit.o
$(OBJDIR)/mod_lorentz_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o
$(OBJDIR)/mod_multiphase.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_momentum_3d.o $(OBJDIR)/mod_pressure_3d.o $(OBJDIR)/mod_energy_3d.o $(OBJDIR)/mod_continuity.o $(OBJDIR)/mod_drag_ergun.o $(OBJDIR)/mod_properties_3d.o $(OBJDIR)/mod_fields_3d.o
$(OBJDIR)/mod_turbulence_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_solver_3d.o $(OBJDIR)/mod_boundary_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_face_flux.o $(OBJDIR)/mod_workspace.o
$(OBJDIR)/mod_radiation_do.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_solver_3d.o $(OBJDIR)/mod_melting_3d.o $(OBJDIR)/mod_audit.o $(OBJDIR)/mod_workspace.o
$(OBJDIR)/mod_chemistry_carbon.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_melting_3d.o $(OBJDIR)/mod_audit.o
$(OBJDIR)/mod_species_transport.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_solver_3d.o $(OBJDIR)/mod_boundary_3d.o $(OBJDIR)/mod_parallel_utils.o $(OBJDIR)/mod_face_flux.o $(OBJDIR)/mod_workspace.o
$(OBJDIR)/mod_convergence_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_mpi_topology.o
$(OBJDIR)/mod_input_profiles.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o
$(OBJDIR)/mod_fields_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_mpi_topology.o $(OBJDIR)/mod_melting_3d.o
$(OBJDIR)/mod_output_hdf5.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_mpi_topology.o
$(OBJDIR)/main_3d.o: $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types_3d.o $(OBJDIR)/mod_mpi_topology.o \
                      $(OBJDIR)/mod_config_3d.o $(OBJDIR)/mod_mesh_3d.o $(OBJDIR)/mod_fields_3d.o \
                      $(OBJDIR)/mod_output_hdf5.o $(OBJDIR)/mod_solver_3d.o $(OBJDIR)/mod_boundary_3d.o \
                      $(OBJDIR)/mod_energy_3d.o $(OBJDIR)/mod_properties_3d.o $(OBJDIR)/mod_momentum_3d.o \
                      $(OBJDIR)/mod_pressure_3d.o $(OBJDIR)/mod_drag_ergun.o $(OBJDIR)/mod_continuity.o \
                      $(OBJDIR)/mod_multiphase.o $(OBJDIR)/mod_solid_phase.o $(OBJDIR)/mod_melting_3d.o \
                      $(OBJDIR)/mod_scrap_collapse.o $(OBJDIR)/mod_interphase_ht.o \
                      $(OBJDIR)/mod_arc_cassie_mayr.o $(OBJDIR)/mod_slag_3d.o \
                      $(OBJDIR)/mod_electrode_3d.o \
                      $(OBJDIR)/mod_arc_radiation_mc.o \
                      $(OBJDIR)/mod_lorentz_3d.o $(OBJDIR)/mod_turbulence_3d.o $(OBJDIR)/mod_radiation_do.o \
                      $(OBJDIR)/mod_chemistry_carbon.o $(OBJDIR)/mod_species_transport.o \
                      $(OBJDIR)/mod_convergence_3d.o \
                      $(OBJDIR)/mod_input_profiles.o $(OBJDIR)/mod_parallel_utils.o \
                      $(OBJDIR)/mod_audit.o

clean:
	rm -rf $(OBJDIR) $(BINDIR) $(TESTBIN)
	rm -f *.mod

#------------------------------------------------------------------------------
# Tests (ver tests/README.md)
#   test-unit       : unit tests Fortran de kernels (tests/unit/*.f90)
#   test-quick      : gate por commit (~1 min): corrida fría + invariantes
#   test-full       : gate por etapa (~10 min): unit + matriz completa
#   test-rebaseline : regenera el golden de métricas (STAGE=v1 make test-rebaseline)
#------------------------------------------------------------------------------
TESTBIN   = tests/bin
UNIT_SRCS = $(wildcard tests/unit/*.f90)
UNIT_BINS = $(patsubst tests/unit/%.f90, $(TESTBIN)/%, $(UNIT_SRCS))
OBJS_LIB  = $(filter-out $(OBJDIR)/main_3d.o, $(OBJS))

.PHONY: test-unit test-quick test-full test-rebaseline

$(TESTBIN)/%: tests/unit/%.f90 $(OBJS)
	@mkdir -p $(TESTBIN)
	$(FC) $(FFLAGS) -I$(OBJDIR) -o $@ $< $(OBJS_LIB) $(HDF5_LIBS)

test-unit: dirs $(UNIT_BINS)
	@bash tests/run_unit.sh

test-quick: all
	@bash tests/run_tests.sh quick

test-full: all test-unit
	@bash tests/run_tests.sh full

test-rebaseline: all
	@bash tests/run_tests.sh rebaseline
