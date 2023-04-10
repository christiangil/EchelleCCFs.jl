"""
Author: Eric Ford
Created: September 2020
"""

#module FitTemplateToCCF

#import ..RVFromCCF: AbstractMeasureRvFromCCF, MeasureRvFromCCFQuadratic
# packages
using LinearAlgebra

# TODO: export once passes test that it's working
#export MeasureRvFromCCFTemplateNonDiagCovar

"""  Functor to estimate RV based on fitting a template and its derivative near minimum of the CCF. """
struct MeasureRvFromCCFTemplateNonDiagCovar <: AbstractMeasureRvFromCCF
    v_grid::AbstractVector{Float64}
    template::AbstractVector{Float64}
    deriv::AbstractVector{Float64}
    mean_var::Float64
    near_diag_covar::AbstractArray{Float64,2}
    v_idx_to_fit::UnitRange{Int64}
end

#=
# Todo: Replace with version in RvSpectMLBase or a (brute force?/temporal?) GP?
function numerical_deriv( x::AA1, y::AA2 )   where { T1<:Real, AA1<:AbstractArray{T1,1}, T2<:Real, AA2<:AbstractArray{T2,1}  }
	@assert length(x) == length(y)
	dydx = zeros(size(y))
	dydx[1] = (y[2]-y[1])/(x[2]-x[1])
	dydx[2:end-1] .= (y[3:end].-y[1:end-2])./(x[3:end].-x[1:end-2])
	dydx[end] = (y[end]-y[end-1])/(x[end]-x[end-1])
	return dydx
end
=#

"""
Construct functor to estimate RV based on the CCF.
TODO: Implement correctly.  Not yet working/tested.
Optional Arguments:
- `v_grid`:  list of velocities where template is evaluated
- `template`: template ccf evaluated at v_grid
- `frac_of_width_to_fit`: (0.5)
- `measure_width_at_frac_depth`: (0.5)
"""
function MeasureRvFromCCFTemplateNonDiagCovar(; v_grid::AbstractVector{T1},
                                    		template::AbstractVector{T2},
						frac_of_width_to_fit::Real = default_frac_of_width_to_fit,
                                    		measure_width_at_frac_depth::Real = default_measure_width_at_frac_depth,
						mean_var::Real = 0,
						near_diag_covar::AbstractArray{T3,2} = zeros(length(v_grid),length(v_grid))
                                     		) where { T1<:Real, T2<:Real, T3<:Real }
    @assert length(v_grid) == length(template)
    @assert length(v_grid) >= 3
    @assert 0.25 <= measure_width_at_frac_depth <= 0.75
    @assert 0.1 <= frac_of_width_to_fit <= 5.0  # TODO: FIgure out appropriate range
    @assert 0 <= mean_var < Inf
    # Estimate derivative
    deriv = numerical_deriv(v_grid, template)
    # find the min and fit only the part near the minimum of the CCF
    v_min, v_idx_to_fit = find_idx_at_and_around_minimum(v_grid, template, frac_of_width_to_fit=frac_of_width_to_fit, measure_width_at_frac_depth=measure_width_at_frac_depth)
    #near_diag_covar = zeros(length(v_grid),length(v_grid))
    MeasureRvFromCCFTemplateNonDiagCovar(v_grid, template, deriv, mean_var, near_diag_covar, v_idx_to_fit)
end

function set_mean_var(in::MeasureRvFromCCFTemplateNonDiagCovar, mean_var::Real)
	MeasureRvFromCCFTemplateNonDiagCovar(v_grid=in.v_grid,template=in.template, mean_var=mean_var, near_diag_covar=in.near_diag_covar )
end

function (mrv::MeasureRvFromCCFTemplateNonDiagCovar)(vels::A1, ccf::A2, ccf_var::A3, ccf_covar::A4  ) where {T1<:Real, A1<:AbstractArray{T1,1}, T2<:Real, A2<:AbstractArray{T2,1}, T3<:Real, A3<:AbstractArray{T3,1}, T4<:Real, A4<:AbstractArray{T4,2}  }
		@assert all(vels .== mrv.v_grid)  # Could relax this, but keep it simple for now
		# fit only the part near the minimum of the CCF
		deriv = view(mrv.deriv,mrv.v_idx_to_fit)
		diag_scale_factor = mean(ccf_var)-mrv.mean_var
		covar = view(ccf_covar,mrv.v_idx_to_fit,mrv.v_idx_to_fit) + diag_scale_factor*view(mrv.near_diag_covar,mrv.v_idx_to_fit,mrv.v_idx_to_fit)
        # find the min and fit only the part near the minimum of the CCF
		ccf_inv_covar_times_deriv = covar \ deriv
		denom = deriv' * ccf_inv_covar_times_deriv
		# Minus sign due to weird convention of defining CCF to look like an absorption line (e.g., 1 at Inf minimum at best fit velocity)
		rv = -(view(ccf,mrv.v_idx_to_fit) .- view(mrv.template,mrv.v_idx_to_fit) )' * ccf_inv_covar_times_deriv
		rv *= (1/denom)
		σ_rv = sqrt(1/denom)
		return (rv=rv, σ_rv=σ_rv)
end
