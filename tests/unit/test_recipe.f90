!===============================================================================
! test_recipe.f90 - read_charge_recipe: receta sintética altera la carga
! y el fallback al default funciona (C4.4).
!===============================================================================
program test_recipe
    use mod_constants
    use mod_types_3d
    use mod_input_profiles
    implicit none

    type(config_t) :: cfg
    integer :: iu, nfail

    nfail = 0

    ! Receta sintética: 2 capas B1 + 1 capa B2
    open(newunit=iu, file='test_recipe_tmp.dat', status='replace')
    write(iu,'(A)') '# sintetica'
    write(iu,'(A)') '1  1000.0  0.60'
    write(iu,'(A)') '1  2000.0  0.40'
    write(iu,'(A)') '2  3000.0  0.55'
    close(iu)

    call read_charge_recipe(cfg, 'test_recipe_tmp.dat')
    if (cfg%n_layers_total /= 3) nfail = nfail + 1
    if (cfg%n_layers_b1 /= 2 .or. cfg%n_layers_b2 /= 1) nfail = nfail + 1
    if (abs(cfg%layer_mass(2) - 2000.0_dp) > 1e-12_dp) nfail = nfail + 1
    if (abs(cfg%layer_vfrac(3) - 0.55_dp) > 1e-12_dp) nfail = nfail + 1
    if (cfg%layer_bucket(3) /= 2) nfail = nfail + 1

    ! Fallback: archivo inexistente -> default (27 capas, 14+13)
    call read_charge_recipe(cfg, 'no_existe_xyz.dat')
    if (cfg%n_layers_total /= 27) nfail = nfail + 1
    if (cfg%n_layers_b1 /= 14 .or. cfg%n_layers_b2 /= 13) nfail = nfail + 1
    if (abs(sum(cfg%layer_mass(1:14)) - 65700.0_dp) > 1e-6_dp) nfail = nfail + 1

    open(newunit=iu, file='test_recipe_tmp.dat', status='old')
    close(iu, status='delete')

    if (nfail > 0) then
        print '(A,I0,A)', 'test_recipe: FAIL (', nfail, ' checks)'
        stop 1
    end if
    print '(A)', 'test_recipe: PASS'
end program test_recipe
