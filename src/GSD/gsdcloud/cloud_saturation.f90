SUBROUTINE cloud_saturation(mype,l_conserve_thetaV,i_conserve_thetaV_iternum,r_cloudfrac_threshold, &
                 cld_bld_coverage, &
                 nlat,nlon,nsig,q_bk,t_bk,p_bk,cldfrabk, &
                 cld_cover_3d,wthr_type,  &
                 cldwater_3d,cldice_3d,sumqci,qv_max_inc)
!
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:  cloud_saturation  to ensure water vapor saturation at all cloudy grid points
!                               also to ensure sub saturation in clear point
!
!   PRGMMR: Ming Hu          ORG: GSD/AMB        DATE: 2006-11-20
!
! ABSTRACT: 
!  This subroutine calculate liquid water content for stratiform cloud
!
! PROGRAM HISTORY LOG:
!    2010-10-06  Hu  check whole 3D mositure field and get rid of supersaturation
!    2009-01-20  Hu  Add NCO document block
!    2017-04-13  Ladwig Add comments & theta-v conservation for missing obs case
!
!
!   input argument list:
!     nlon        - no. of lons on subdomain (buffer points on ends)
!     nlat        - no. of lats on subdomain (buffer points on ends)
!     nsig        - no. of levels
!     q_bk        - 3D moisture
!     t_bk        - 3D background potential temperature (K)
!     p_bk        - 3D background pressure  (hPa)
!     cldfrabk    - 3D background cloud fraction (0 to 1)
!     cldwater_3d - 3D analysis cloud water mixing ratio (g/kg)
!     cldice_3d   - 3D analysis cloud ice mixing ratio (g/kg)
!     cld_cover_3d- 3D cloud cover
!     wthr_type   - 3D weather type
!     l_conserve_thetaV  - if .true. conserving thetaV
!     i_conserve_thetaV_iternum - iteration number for conserving thetaV
!     cld_bld_coverage - fraction of cloud coverage to active building behavior,
!                      - default 0.6
!
!   output argument list:
!     q_bk        - 3D moisture
!
! USAGE:
!   INPUT FILES: 
!
!   OUTPUT FILES:
!
! REMARKS:
!
! ATTRIBUTES:
!   LANGUAGE: FORTRAN 90 
!   MACHINE:  Linux cluster (WJET)
!
!$$$
!
!_____________________________________________________________________
!

  use constants, only: rd_over_cp, h1000,one,zero,fv
  use gsd_kinds, only: r_single,i_kind, r_kind

  implicit none

  integer(i_kind),intent(in):: mype
  integer(i_kind),intent(in):: nlat,nlon,nsig
  logical,intent(in):: l_conserve_thetaV
  integer(i_kind),intent(in):: i_conserve_thetaV_iternum
  integer(r_single),intent(in):: r_cloudfrac_threshold 
  integer(r_single),intent(in):: cld_bld_coverage
!
!  background
!
  real(r_single),intent(inout)    :: t_bk(nlon,nlat,nsig)   ! potential temperature (K)
  real(r_single),intent(inout) :: q_bk(nlon,nlat,nsig)   ! mixing ratio (kg/kg)
  real(r_single),intent(in)    :: p_bk(nlon,nlat,nsig)   ! pressure  (hpa)
  real(r_single),intent(in)    :: cldfrabk(nlon,nlat,nsig)   ! cloud fraction
  REAL(r_kind),intent(in)      :: sumqci(nlon,nlat,nsig)  ! total liquid water
  real(r_kind),intent(in)    :: qv_max_inc             ! max qv increment
!
!  Variables for cloud analysis
!
  real (r_single),intent(in) :: cld_cover_3d(nlon,nlat,nsig) 
  integer(i_kind),intent(in) :: wthr_type(nlon,nlat)   
!
! cloud water and cloud ice
!
  real (r_single),intent(in) :: cldwater_3d(nlon,nlat,nsig) ! kg/kg
  real (r_single),intent(in) :: cldice_3d(nlon,nlat,nsig)   ! kg/kg
!-----------------------------------------------------------
!
! temp.
!
  INTEGER(i_kind) :: i,j,k
  real(r_single) :: cloudqvis,ruc_saturation

! --- Key parameters
!     Rh_clear_p        = 0.80          RH to use when clearing cloud

  real(r_single)    rh_cld3_p
  real(r_single)    rh_clear_p
  data  rh_cld3_p         /0.98_r_single/    ! mhu, do we need to adjust this number to 0.94, WPP has PBL top set as 0.95
  data  rh_clear_p        /0.8_r_single/

  real(r_kind) ::  es0_p
  parameter (es0_p=6.1121_r_kind)     ! saturation vapor pressure (mb)

  INTEGER(i_kind) :: miter,nnn

  REAL(r_kind) :: constantTv, Temp
  real(r_single) :: qtemp
!
!====================================================================
!  Begin
!
!
  miter=i_conserve_thetaV_iternum   ! iteration number for conserving Tv

  DO j = 2,nlat-1
    DO i = 2,nlon-1
      DO k = 2,nsig-1

!mhu        p_pa_1d(k) = p_bk(i,j,k)*100.0_r_single
!        qv= q_bk(i,j,k)/(one+q_bk(i,j,k))     !  qv = water vapor specific humidity
!                                              !  q_bk = water vapor mixing ratio
! now, tmperature from GSI s potential temperature. get temperature
        Temp = t_bk(i,j,k)*(p_bk(i,j,k)/h1000)**rd_over_cp

! now, calculate saturation
!
        cloudqvis= ruc_saturation(Temp,p_bk(i,j,k)) 
!
! moisture adjustment based on cloud
!
!
! check each grid point to make sure no supersaturation
        q_bk(i,j,k) = min(q_bk(i,j,k), cloudqvis * 1.00_r_single)
! now, calculate constant virtual temperature
        constantTv=Temp*(one + fv*q_bk(i,j,k))     
!


        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        ! If valid cld_cover_3d
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        if(cld_cover_3d(i,j,k) > -0.0001_r_kind .and.           &
           cld_cover_3d(i,j,k) < 2.0_r_kind) then
          !#############################################
          ! if clear ob
          !#############################################
          if(cld_cover_3d(i,j,k) <= 0.0001_r_kind) then
          ! adjust RH to be below 85 percent(50%?) if
          !     1) cloudyn = 0
          !     2) at least 100 mb above sfc
          !     3) no precip from sfc obs
          !make sure that clear volumes are no more than rh_clear_p RH.
            if( (sumqci(i,j,k))>1.0e-12_r_kind .and.  &
                (p_bk(i,j,1) - p_bk(i,j,k))>100._r_kind  .and.  &
                 wthr_type(i,j) <=0 ) then 
                 if( q_bk(i,j,k) > cloudqvis * rh_clear_p) then
                    qtemp =  cloudqvis * rh_clear_p
                    if(l_conserve_thetaV) then
                       do nnn=1,miter
                          Temp=constantTv/(one + fv*qtemp)
                          cloudqvis= ruc_saturation(Temp,p_bk(i,j,k))
                          qtemp = cloudqvis * rh_clear_p
                       enddo
                       t_bk(i,j,k) = Temp*(h1000/p_bk(i,j,k))**rd_over_cp
                    endif
                    !limit increment
                    q_bk(i,j,k) = min(qtemp, q_bk(i,j,k)+qv_max_inc)
                 endif
            endif
            !C  - moisten layers above and below cloud layer
            if(cld_cover_3d(i,j,k+1) > cld_bld_coverage .or.          &
               cld_cover_3d(i,j,k-1) > cld_bld_coverage  ) then
                 if( cloudqvis > q_bk(i,j,k) ) then
                    qtemp = q_bk(i,j,k) + 0.7_r_single* (cloudqvis-q_bk(i,j,k))
                    if(l_conserve_thetaV) then
                       do nnn=1,miter
                          Temp=constantTv/(one + fv*qtemp)
                          cloudqvis= ruc_saturation(Temp,p_bk(i,j,k))
                          qtemp = q_bk(i,j,k) + 0.7_r_single* (cloudqvis-q_bk(i,j,k))
                       enddo
                       t_bk(i,j,k) = Temp*(h1000/p_bk(i,j,k))**rd_over_cp
                    endif
                    !limit increment
                    q_bk(i,j,k) = min(qtemp, q_bk(i,j,k)+qv_max_inc)
                 endif
            endif
          !#############################################
          ! -- If SCT/FEW present 
          !         
          !#############################################
          elseif(cld_cover_3d(i,j,k) > 0.0001_r_kind .and.      &
                 cld_cover_3d(i,j,k) < cld_bld_coverage ) then
             ! if cloud fraction does not represent partial cloud
             if( cldfrabk(i,j,k) < r_cloudfrac_threshold) then
               if( q_bk(i,j,k) < cloudqvis * rh_cld3_p) then
                 qtemp =  cloudqvis * rh_cld3_p
                 if(l_conserve_thetaV) then
                    do nnn=1,miter
                       Temp=constantTv/(one + fv*qtemp)
                       cloudqvis= ruc_saturation(Temp,p_bk(i,j,k))
                       qtemp = cloudqvis * rh_cld3_p
                    enddo
                 t_bk(i,j,k) = Temp*(h1000/p_bk(i,j,k))**rd_over_cp
                 endif
                 !limit increment
                 q_bk(i,j,k) = min(qtemp, q_bk(i,j,k)+qv_max_inc)
               endif
             endif
          !#############################################
          ! else: cld_cover_3d is > cld_bld_coverage: cloudy case
          !#############################################
          else   ! set qv at 102%RH
             if( q_bk(i,j,k) < cloudqvis * 1.00_r_single ) then
                qtemp = cloudqvis * 1.00_r_single
                if(l_conserve_thetaV) then
                   do nnn=1,miter
                      Temp=constantTv/(one + fv*qtemp)     
                      cloudqvis= ruc_saturation(Temp,p_bk(i,j,k)) 
                      qtemp = cloudqvis * 1.00_r_single
                   enddo
                   t_bk(i,j,k) = Temp*(h1000/p_bk(i,j,k))**rd_over_cp
                endif
                !limit increment
                q_bk(i,j,k) = min(qtemp, q_bk(i,j,k)+qv_max_inc)
             endif
          endif
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        ! cld_cover_3d is missing
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        else    ! cloud cover is missing
        !  Ensure saturation in all cloudy volumes.
        !  Since saturation has already been ensured for new cloudy areas (cld_cover_3d > 0.6)
        !  we now ensure saturation for all cloud 3-d points, whether cloudy from background
        !   (and not changed - cld_cover_3d < 0)
        !  If cloud cover is missing, (cldwater_3d(i,j,k)+cldice_3d(i,j,k) = sumqci(i,j,k), 
        !    which is background cloud liquid water.
          if ((cldwater_3d(i,j,k)+cldice_3d(i,j,k))>1.0e-5_r_kind) then 
              !conserve
              qtemp = cloudqvis * 1.00_r_single
              if(l_conserve_thetaV) then
                   do nnn=1,miter
                      Temp=constantTv/(one + fv*qtemp)
                      cloudqvis= ruc_saturation(Temp,p_bk(i,j,k))
                      qtemp = cloudqvis * 1.00_r_single
                   enddo
                   t_bk(i,j,k) = Temp*(h1000/p_bk(i,j,k))**rd_over_cp
              endif
              !limit increment
              q_bk(i,j,k) = min(qtemp, q_bk(i,j,k)+qv_max_inc)
          endif
        endif   
!
! check each grid point to make sure no supersaturation
!
        q_bk(i,j,k) = min(q_bk(i,j,k), cloudqvis * 1.00_r_single)
!

      enddo ! k
    enddo   ! i
  enddo     ! j

END SUBROUTINE cloud_saturation   

function ruc_saturation(Temp,pressure)
!
!$$$  subprogram documentation block
!                .      .    .                                       .
! subprogram:  ruc_saturation calculate saturation
!
!   PRGMMR: Ming Hu          ORG: GSD/AMB        DATE: 2011-11-28
!
! ABSTRACT: 
!  This subroutine calculate saturation
!
! PROGRAM HISTORY LOG:
!    2011-11-28  Hu  Initial 
!
!
!   input argument list:
!     pressure    - background pressure  (hPa)
!     Temp        - temperature (K)
!
!   output argument list:
!     ruc_saturation
!
! USAGE:
!   INPUT FILES: 
!
!   OUTPUT FILES:
!
! REMARKS:
!
! ATTRIBUTES:
!   LANGUAGE: FORTRAN 90 
!   MACHINE:  Linux cluster (WJET)
!
!$$$
!
!_____________________________________________________________________

  use constants, only: rd_over_cp, h1000,one,zero
  use gsd_kinds, only: r_single,i_kind, r_kind
!
    implicit none
    real(r_single) :: ruc_saturation

    REAL(r_kind),  intent(in) :: Temp       ! temperature in K
    real(r_single),intent(in) :: pressure   ! pressure  (hpa)

    real(r_kind) ::  es0_p
    parameter (es0_p=6.1121_r_kind)     ! saturation vapor pressure (mb)
    real(r_kind) SVP1,SVP2,SVP3
    data SVP1,SVP2,SVP3/es0_p,17.67_r_kind,29.65_r_kind/

    real(r_kind) :: temp_qvis1, temp_qvis2
    data temp_qvis1, temp_qvis2 /268.15_r_kind, 263.15_r_kind/

    REAL(r_kind) :: evs, qvs1, eis, qvi1, watwgt
!

!
! evs, eis in mb
!   For this part, must use the water/ice saturation as f(temperature)
        evs = svp1*exp(SVP2*(Temp-273.15_r_kind)/(Temp-SVP3))
        qvs1 = 0.62198_r_kind*evs/(pressure-evs)  ! qvs1 is mixing ratio kg/kg
                                                     !  so no need next line
!      qvs1 = qvs1/(1.0-qvs1)
!   Get ice saturation and weighted ice/water saturation ready to go
!    for ensuring cloud saturation below.
        eis = svp1 *exp(22.514_r_kind - 6.15e3_r_kind/Temp)
        qvi1 = 0.62198_r_kind*eis/(pressure-eis)  ! qvi1 is mixing ratio kg/kg,
                                                     ! so no need next line
!      qvi1 = qvi1/(1.0-qvi1)
!      watwgt = max(0.,min(1.,(Temp-233.15)/(263.15-233.15)))
!      watwgt = max(zero,min(one,(Temp-251.15_r_kind)/&
!                        (263.15_r_kind-251.15_r_kind)))
! ph - 2/7/2012 - use ice mixing ratio only for temp < 263.15
        watwgt = max(zero,min(one,(Temp-temp_qvis2)/&
                              (temp_qvis1-temp_qvis2)))
        ruc_saturation= (watwgt*qvs1 + (one-watwgt)*qvi1)  !  kg/kg
!
end function ruc_saturation
