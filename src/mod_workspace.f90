!===============================================================================
! mod_workspace.f90 - Workspace persistente de coeficientes (C4.1, hallazgo 3.22a)
!
! Los 7 ensambladores (momentum, energía, especies, k-eps, fracción de
! volumen, presión, radiación DO) alocaban/dealocaban los 8 arrays de
! coeficientes en CADA llamada (~24 alloc/dealloc de campos completos por
! iteración externa). Aquí viven una sola vez, con los halos estándar
! (-1:n+2). Es seguro compartirlos porque:
!   (a) cada rank es mono-hilo y los ensambladores nunca se anidan, y
!   (b) TODOS los ensambladores ceran los 8 arrays completos antes de
!       usarlos, así que el contenido previo jamás se lee
! => el cambio es BIT-idéntico por construcción (verificado con h5diff).
!
! Uso en cada ensamblador:
!     use mod_workspace, only: ensure_workspace, aW => ws_aW, ... , Su => ws_Su
!     ...
!     call ensure_workspace(m)
!===============================================================================
module mod_workspace
    use mod_constants
    use mod_types_3d
    implicit none

    real(dp), allocatable :: ws_aW(:,:,:), ws_aE(:,:,:)
    real(dp), allocatable :: ws_aS(:,:,:), ws_aN(:,:,:)
    real(dp), allocatable :: ws_aB(:,:,:), ws_aT(:,:,:)
    real(dp), allocatable :: ws_aP(:,:,:), ws_Su(:,:,:)

contains

    subroutine ensure_workspace(m)
        type(mesh_t), intent(in) :: m

        if (allocated(ws_aP)) return
        allocate(ws_aW(-1:m%nr+2, -1:m%ntheta+2, -1:m%nz+2))
        allocate(ws_aE, ws_aS, ws_aN, ws_aB, ws_aT, ws_aP, ws_Su, mold=ws_aW)
    end subroutine ensure_workspace

end module mod_workspace
