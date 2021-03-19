#=
Emitters are defined by Pixels and SpatialLayouts. An emitter has a spectrum, and an optical power distribution over the hemisphere. 
These are intrinsic physical properties of the emitter.
=#

module Emitters

import ..OpticSim
# import Makie
# import Makie.AbstractPlotting
# import Makie.AbstractPlotting.MakieLayout

# using LinearAlgebra
# # import  Distributions
# using DataFrames
# using StaticArrays
# using Unitful

struct MissingImplementationException <: Exception
    msg::String
end

# defining name placeholders to override in nested modules
generate() = 0 
export generate
visual_size() = 0
export visual_size
apply() = 0
export apply

# time measuring macro with a caption
macro timeCap(caption, ex)
    quote
        print("[Timing] [$($caption)] ")
        @time $(esc(ex))
    end
end
export @timeCap


#------------------------------------------------------------------------------
# Geometry
#------------------------------------------------------------------------------
#region Geometry
module Geometry     

import OpticSim
using LinearAlgebra
using StaticArrays


struct Vec3D{T} <: FieldVector{3, T}
    x::T
    y::T
    z::T
end

unitX(::Type{T} = Float64) where {T<:Real} = Vec3D{T}(one(T), zero(T), zero(T))
unitY(::Type{T} = Float64) where {T<:Real} = Vec3D{T}(zero(T), one(T), zero(T))
unitZ(::Type{T} = Float64) where {T<:Real} = Vec3D{T}(zero(T), zero(T), one(T))
OpticSim.origin(::Type{T} = Float64) where {T<:Real} = Vec3D{T}(zero(T), zero(T), zero(T))
export unitX, unitY, unitZ, origin

function get_orthogonal_vectors(direction::Vec3D{T}) where {T<:Number}
    axis1 = normalize(direction)

    dp = dot(unitX(T), axis1)
    if	( dp >= one(T) - eps(T))
        axis1 = unitX(T);
        axis2 = unitY(T);
        axis3 = unitZ(T);
        return (axis2, axis3)
    elseif  ( dp <= -one(T) + eps(T))
        axis1 = -unitX(T);
        axis2 = -unitY(T);
        axis3 = -unitZ(T);
        return (axis2, axis3)
    end

    axis3 = normalize(cross(axis1, unitX(T)))
    axis2 = normalize(cross(axis3, axis1))
    return (axis2, axis3)
end

#---------------------------------------
# 3D Transform / Local Frame
#---------------------------------------
struct Transform{T} 
    m_origin::Vec3D{T}
    right::Vec3D{T}     # x
    up::Vec3D{T}        # y
    forward::Vec3D{T}   # z
    scale::Vec3D{T}

    # function Transform(::Type{T} = Float64) where {T<:Real}
    #     return new{T}(origin(T), unitX(T), unitY(T), unitZ(T), Vec3D(one(T), one(T), one(T)))
    # end

    function Transform(position::Vec3D{T} = OpticSim.origin(), forward::Vec3D{T} = unitZ(), ::Type{T} = Float64) where {T<:Real}
        forward = normalize(forward)
        right, up = get_orthogonal_vectors(forward)
        return new{T}(position, right, up, forward, Vec3D(one(T), one(T), one(T)))
    end

    function Transform(mat::SMatrix{4, 4, T}) where {T<:Real}
        rot, t, s = decomposeRTS(mat)
        o = t
        r = Vec3D(rot[1:3,1])
        u = Vec3D(rot[1:3,2])
        f = Vec3D(rot[1:3,3])
        return new{T}(o, r, u, f, s)
    end

end


OpticSim.origin(t::Transform{T}) where {T<:Real} = t.m_origin
right(t::Transform{T}) where {T<:Real} = t.right
up(t::Transform{T}) where {T<:Real} = t.up
forward(t::Transform{T}) where {T<:Real} = t.forward
scale(t::Transform{T}) where {T<:Real} = t.scale

function rotation(t::Transform{T}) where {T<:Real}
    return SMatrix{3, 3}(t.right..., t.up..., t.forward...)
end
export rotation

function translation(t::Transform{T}) where {T<:Real}
    return OpticSim.origin(t)
end
export translation

function rotationMat(t::Transform{T}) where {T<:Real}
    return SMatrix{4, 4}(t.right..., 0, t.up..., 0, t.forward..., 0, 0, 0, 0, 1)
end
export rotationMat

function translationMat(t::Transform{T}) where {T<:Real}
    return SMatrix{4, 4}(one(T), zero(T), zero(T), zero(T), zero(T), one(T), zero(T), zero(T), zero(T), zero(T), one(T), zero(T), t.m_origin..., 1)
end
export translationMat

function scaleMat(t::Transform{T}) where {T<:Real}
    return SMatrix{4, 4}(t.scale[1], zero(T), zero(T), zero(T), zero(T), t.scale[2], zero(T), zero(T), zero(T), zero(T), t.scale[3], zero(T), zero(T), zero(T), zero(T), one(T))
end
export scaleMat

function local2worldMat(t::Transform{T}) where {T<:Real}
    return scaleMat(t) * translationMat(t) * rotationMat(t)  
end
export local2worldMat

function decomposeRTS(mat::SMatrix{4, 4, T}) where {T<:Real}
    t = Vec3D{T}(mat[1,4], mat[2, 4], mat[3, 4])
    sx = norm(Vec3D{T}(mat[1,1], mat[2, 1], mat[3, 1]))
    sy = norm(Vec3D{T}(mat[1,2], mat[2, 2], mat[3, 2]))
    sz = norm(Vec3D{T}(mat[1,3], mat[2, 3], mat[3, 3]))
    s = Vec3D{T}(sx, sy, sz)
    rot = SMatrix{4, 4, T}(mat[1,1]/sx, mat[2, 1]/sx, mat[3,1]/sx, 0, mat[1,2]/sy, mat[2, 2]/sy, mat[3,2]/sy, 0, mat[1,3]/sz, mat[2, 3]/sz, mat[3,3]/sz, 0, 0, 0, 0, 1)

    return rot, t, s
end
export decomposeRTS


function Base.:*(x::Transform{T}, y::Transform{T}) where {T<:Real}
    mat = local2worldMat(x) * local2worldMat(y)
    return Transform(mat)
end

function Base.:*(tr::Transform{T}, ray::OpticSim.Ray{T, 3}) where {T<:Real}
    o = local2world(tr, OpticSim.origin(ray))    
    d = rotate(tr, OpticSim.direction(ray))    
    return OpticSim.Ray(o, d)
end

function Base.:*(tr::Transform{T}, ray::OpticSim.OpticalRay{T}) where {T<:Real}
    r = tr * ray.ray
    or = OpticSim.OpticalRay(r, ray.power, ray.wavelength; opl=ray.opl, nhits=ray.nhits, sourcenum=ray.sourcenum, sourcepower=ray.sourcepower)
    return or
    # return OpticSim.OpticalRay(OpticSim.origin(r), OpticSim.direction(r), ray.power, ray.wavelength, ray.opl, ray.nhits, ray.sourcenum, ray.sourcepower)
end



function local2world(t::Transform{T},  v::AbstractVector{T}) where {T<:Real}
    return OpticSim.origin(t) + (v[1] * right(t) + v[2] * up(t) + v[3] * forward(t));
end


function local2worldRBT(t::Transform{T}) where {T<:Real}
    return OpticSim.RigidBodyTransform(rotation(T), OpticSim.origin(t))
end

function rotate(t::Transform{T}, v::AbstractVector{T}) where {T<:Real}
    return rotation(t) * v
end

function rotXmat(angle::T, ::Type{T} = Float64) where {T<:Real} 
    # constructor is column major

    c = cos(angle)
    s = sin(angle)

    return SMatrix{3,3,T,9}(
        one(T), zero(T), zero(T),
        zero(T), c, s,
        zero(T), -s, c
    )
    
end

function rotYmat(angle::T, ::Type{T} = Float64) where {T<:Real} 
    # constructor is column major

    c = cos(angle)
    s = sin(angle)

    return SMatrix{3,3,T,9}(
        c, zero(T), s,
        zero(T), one(T), zero(T),
        -s, zero(T), c
    )
    
end

function rotZmat(angle::T, ::Type{T} = Float64) where {T<:Real} 
    # constructor is column major

    c = cos(angle)
    s = sin(angle)

    return SMatrix{3,3,T,9}(
        c, -s, zero(T),
        s, c, zero(T),
        zero(T), zero(T), one(T)
    )
    
end

function rotAxisMat(axis::SVector{3, T}, angle::T, ::Type{T} = Float64) where {T<:Real} 
    c = cos(-angle);
    s = sin(-angle);
    t = one(T) - c;

    axis = normalize(axis)

    return SMatrix{3,3,T,9}(
        t * axis[1] * axis[1] + c, t * axis[1] * axis[2] + s * axis[3], t * axis[1] * axis[3] - s * axis[2],
        t * axis[1] * axis[2] - s * axis[3], t * axis[2] * axis[2] + c, t * axis[2] * axis[3] + s * axis[1],
        t * axis[1] * axis[3] + s * axis[2], t * axis[2] * axis[3] - s * axis[1], t * axis[3] * axis[3] + c
    )
end


#---------------------------------------
# exports
#---------------------------------------
export  Vec3D, unitX, unitY, unitZ, origin, Transform,
        get_orthogonal_vectors,
        Transform, origin, right, up, forward, scale, rotation, translation, local2world, local2worldMat, local2worldRBT, rotate,
        rotXmat, rotYmat, rotZmat, rotAxisMat

end # module Geometry
#endregion Geometry


#------------------------------------------------------------------------------
# Spectrum
#------------------------------------------------------------------------------
#region Spectrum
module Spectrum     

import OpticSim
using DataFrames
using Distributions

using ..Emitters

abstract type AbstractSpectrum{T<:Real} end

const UNIFORMSHORT = 0.450 #um
const UNIFORMLONG = 0.680 #um

#---------------------------------------
# Uniform Spectrum
#---------------------------------------
struct Uniform{T} <: AbstractSpectrum{T}
    low_end::T
    high_end::T

    # user defined range of spectrum
    function Uniform(low::T, high::T) where {T<:Real}
        return new{T}(low, high)
    end

    # with no specific range we will use the constants' values
    function Uniform(::Type{T} = Float64) where {T<:Real}
        return new{T}(UNIFORMSHORT, UNIFORMLONG)
    end
end
export Uniform

Emitters.generate(s::Uniform{T}) where {T} = (T(1), rand(Distributions.Uniform(s.low_end, s.high_end)))

#---------------------------------------
# Delta Function Spectrum
#---------------------------------------
struct DeltaFunction{T<:Real} <: AbstractSpectrum{T}
    λ::T
end
export DeltaFunction

Emitters.generate(s::DeltaFunction{T}) where {T} = (T(1), s.λ)

#---------------------------------------
# Measured Spectrum
#---------------------------------------

struct Measured{T<:Real} <: AbstractSpectrum{T}
    low_wave_length::Int
    high_wave_length::Int
    wave_length_step::Int
    power_samples::Vector{T}

    function Measured(samples::DataFrame)
        colnames = names(samples)
        @assert "Wavelength" in colnames
        @assert "Power" in colnames
        wavelengths = samples[!, :Wavelength]
        @assert eltype(wavelengths) <: Integer

        power::Vector{T} where {T<:Real} = samples[!, :Power] # no missing values allowed and must be real numbers
        maxpower = maximum(power)
        T = eltype(power)
        p = sortperm(wavelengths)
        wavelengths = wavelengths[p]
        power = power[p] ./ maxpower #make sure power values have the same sorted permutation as wavelengths normalized with maximum power equal to 1
        λmin = wavelengths[p[1]]
        λmax = wavelengths[p[end]]
        step = wavelengths[2] - wavelengths[1]

        for i in 3:length(wavelengths)
            @assert wavelengths[i] - wavelengths[i - 1] == step  # no missing values allowed and step size must be consistent
        end

        return new{T}(λmin, λmax, step, power)
    end
end
export Measured

"""expects wavelength in nm not um"""
function spectrumpower(spectrum::Measured{T}, λ::T)::Union{Nothing,T} where {T<:Real}
    λ = λ #convert from um to nm
    if λ < spectrum.low_wave_length || λ > spectrum.high_wave_length
        return nothing
    end

    lowindex = floor(Int, (λ - spectrum.low_wave_length)) ÷ spectrum.wave_length_step + 1

    if lowindex == length(spectrum.power_samples)
        return T(spectrum.power_samples[end])
    else
        highindex = lowindex + 1
        α = mod(λ, spectrum.wave_length_step) / spectrum.wave_length_step

        return T((1 - α) * spectrum.power_samples[lowindex] + α * spectrum.power_samples[highindex])
    end
end


function Emitters.generate(s::Measured{T}) where {T}
    spectrum = s
    λ = rand(Distributions.Uniform{T}(T(spectrum.low_wave_length), T(spectrum.high_wave_length)))
    power = spectrumpower(spectrum, λ)
    if power === nothing        #added this condition because the compiler was allocating if just returned values directly.
        return (nothing, nothing)
    else
        return (power, λ / T(1000)) #convert from nm to um
    end
end


end # module Spectrum 
#endregion Spectrum

#------------------------------------------------------------------------------
# Directions Distribution
#------------------------------------------------------------------------------
#region Direction Distribution
module Directions

import OpticSim
using LinearAlgebra
using ..Emitters
using ..Geometry

abstract type AbstractDirectionDistribution{T<:Real} end

#---------------------------------------
# Direction Distrubution Common Utilities
#---------------------------------------

export generate

Base.iterate(a::AbstractDirectionDistribution, state = 1) = state > length(a) ? nothing : (generate(a, state - 1), state + 1)
Base.getindex(a::AbstractDirectionDistribution, index) = generate(a, index)
Base.firstindex(a::AbstractDirectionDistribution) = 0
Base.lastindex(a::AbstractDirectionDistribution) = length(a) - 1
Base.copy(a::AbstractDirectionDistribution) = a # most don't have any heap allocated stuff so don't really need copying


#---------------------------------------
# Constant Ray Direction
#---------------------------------------
struct Constant{T} <: AbstractDirectionDistribution{T}
    direction::Vec3D{T}

    function Constant(direction::Vec3D{T}) where {T<:Real}
        return new{T}(direction)
    end
    
    function Constant(::Type{T} = Float64) where {T<:Real}
        direction = unitZ(T)
        return new{T}(direction)
    end
end
export Constant

Base.length(d::Constant{T}) where {T} = 1
function Emitters.generate(d::Constant{T}, n::Int) where {T<:Real}
    return d.direction
end

#---------------------------------------
# Grid  Ray Distribution
#---------------------------------------
struct RectGrid{T} <: AbstractDirectionDistribution{T}
    direction::Vec3D{T}
    halfangleu::T
    halfanglev::T
    nraysu::Int
    nraysv::Int
    uvec::Vec3D{T}
    vvec::Vec3D{T}

    function RectGrid(direction::Vec3D{T}, halfangleu::T, halfanglev::T, numraysu::Int, numraysv::Int) where {T<:Real}
        (uvec, vvec) = get_uv_vectors(direction)
        return new{T}(direction, halfangleu, halfanglev, numraysu, numraysv, uvec, vvec)
    end

    function RectGrid(halfangleu::T, halfanglev::T, numraysu::Int, numraysv::Int) where {T<:Real}
        direction, uvec, vvec = (unitZ(T), unitX(T), unitY(T))
        return new{T}(direction, halfangleu, halfanglev, numraysu, numraysv, uvec, vvec)
    end
end
export RectGrid

Base.length(d::RectGrid{T}) where {T} = d.nraysu * d.nraysv
function Emitters.generate(d::RectGrid{T}, n::Int) where {T<:Real}
    direction = d.direction
    uvec = d.uvec
    vvec = d.vvec

    # distributing evenly across the area of the rectangle which subtends the given angle (*not* evenly across the angle range)
    dindex = mod(n, d.nraysu * d.nraysv)
    v = d.nraysv == 1 ? zero(T) : 2 * Int(floor(dindex / d.nraysu)) / (d.nraysv - 1) - 1.0
    u = d.nraysu == 1 ? zero(T) : 2 * mod(dindex, d.nraysu) / (d.nraysu - 1) - 1.0
    θu = atan(u * tan(d.halfangleu) / 2) * d.halfangleu
    θv = atan(v * tan(d.halfanglev) / 2) * d.halfanglev
    dir = cos(θv) * (cos(θu) * direction + sin(θu) * uvec) + sin(θv) * vvec
    return dir
end


#---------------------------------------
# Cone Ray Distribution
#---------------------------------------
struct UniformCone{T} <: AbstractDirectionDistribution{T}
    direction::Vec3D{T}
    θmax::T
    numsamples::Int
    uvec::Vec3D{T}
    vvec::Vec3D{T}

    function UniformCone(direction::Vec3D{T}, θmax::T, numsamples::Int) where {T<:Real}
        (uvec, vvec) = get_uv_vectors(direction)
        return new{T}(direction, θmax, numsamples, uvec, vvec)
    end

    function UniformCone(θmax::T, numsamples::Int) where {T<:Real}
        direction, uvec, vvec = (unitZ(T), unitX(T), unitY(T))
        return new{T}(direction, θmax, numsamples, uvec, vvec)
    end
end
export UniformCone

Base.length(d::UniformCone{T}) where {T} = d.numsamples
function Emitters.generate(d::UniformCone{T}, n::Int) where {T<:Real}
    direction = d.direction
    θmax = d.θmax
    uvec = d.uvec
    vvec = d.vvec

    ϕ = rand(T) * 2π
    θ = acos(clamp(one(T) + rand(T) * (cos(θmax) - 1), -one(T), one(T)))
    return normalize(sin(θ) * (cos(ϕ) * uvec + sin(ϕ) * vvec) + cos(θ) * direction)
end

#----------------------------------------------------------------------------
# Cone Ray Hexapolar Distribution
#-----------------------------------------------------------------------------
struct HexapolarCone{T} <: AbstractDirectionDistribution{T}
    direction::Vec3D{T}
    θmax::T
    nrings::Int
    uvec::Vec3D{T}
    vvec::Vec3D{T}

    function HexapolarCone(direction::Vec3D{T}, θmax::T, nrings::Int) where {T<:Real}
        (uvec, vvec) = get_orthogonal_vectors(direction)
        return new{T}(direction, θmax, nrings, uvec, vvec)
    end

    # assume canonical directions
    function HexapolarCone(θmax::T, nrings::Int = 3) where {T<:Real}
        direction, uvec, vvec = (unitZ(T), unitX(T), unitY(T))
        return new{T}(direction, θmax, nrings, uvec, vvec)
    end
end
export HexapolarCone


Base.length(d::HexapolarCone{T}) where {T} = 1 + round(Int, (d.nrings * (d.nrings + 1) / 2) * 6)
function Emitters.generate(d::HexapolarCone{T}, n::Int) where {T<:Real}
    dir = d.direction
    θmax = d.θmax
    uvec = d.uvec
    vvec = d.vvec

    n = mod(n, length(d))
    if n == 0
        return normalize(dir)
    else
        t = 1
        ringi = 1
        for i in 1:(d.nrings)
            t += 6 * i
            if n < t
                ringi = i
                break
            end
        end
        ρ = ringi / d.nrings
        pind = n - (t - 6 * ringi)
        
        ϕ = (pind / (6 * ringi)) * 2π
        # elevation calculated as ring fraction multipled by max angle
        θ = acos(clamp(one(T) +  (cos(ρ * θmax) - 1), -one(T), one(T)))
        return normalize(sin(θ) * (cos(ϕ) * uvec + sin(ϕ) * vvec) + cos(θ) * dir)
    end
end

end # module Directions
#endregion Direction Distribution

#------------------------------------------------------------------------------
# Origins Distribution
#------------------------------------------------------------------------------
#region Origins
module Origins

import OpticSim
using LinearAlgebra
using Distributions
using ..Emitters
using ..Geometry


abstract type AbstractOriginDistribution{T<:Real} end

#---------------------------------------
# Origin Distrubution Common Utilities
#---------------------------------------

Base.iterate(a::AbstractOriginDistribution, state = 1) = state > length(a) ? nothing : (generate(a, state - 1), state + 1)
Base.getindex(a::AbstractOriginDistribution, index) = generateray(a, index)
Base.firstindex(a::AbstractOriginDistribution) = 0
Base.lastindex(a::AbstractOriginDistribution) = length(a) - 1
Base.copy(a::AbstractOriginDistribution) = a # most don't have any heap allocated stuff so don't really need copying

export generate

#--------------------------------------
# Point Origin
#--------------------------------------
struct Point{T} <: AbstractOriginDistribution{T}
    origin::Vec3D{T}

    function Point(position::Vec3D{T}) where {T<:Real}
        return new{T}(position)
    end

    function Point(x::T, y::T, z::T) where {T<:Real}
        return new{T}(Vec3D{T}(x, y, z))
    end

    function Point(::Type{T} = Float64) where {T<:Real}
        return new{T}(OpticSim.origin(T))
    end

end
export Point

Base.length(o::Point{T}) where {T} = 1
Emitters.visual_size(o::Point{T}) where {T} = 1

function Emitters.generate(o::Point{T}, n::Int) where {T<:Real}
    return o.origin
end

#-------------------------------------
# Random Rectangle Origin
#-------------------------------------
struct RectUniform{T} <: AbstractOriginDistribution{T}
    width::T
    height::T
    samples_count::Int

    function RectUniform(width::T, height::T, count::Int) where {T<:Real}
        return new{T}(width, height, count)
    end
end
export RectUniform


Base.length(o::RectUniform{T}) where {T} = o.samples_count
Emitters.visual_size(o::RectUniform{T}) where {T} = max(o.width, o.height)

# generate origin on the agrid
function Emitters.generate(o::RectUniform{T}, n::Int) where {T<:Real}
    n = mod(n, length(o))
    u = rand(Distributions.Uniform(T(-1), T(1)))
    v = rand(Distributions.Uniform(T(-1), T(1)))
    return OpticSim.origin(T) + ((o.width / 2) * u * unitX(T)) + ((o.height/2) * v * unitY(T))
end


#-------------------------------------
# Grid Rectangle Origin
#-------------------------------------
struct RectGrid{T} <: AbstractOriginDistribution{T}
    width::T
    height::T
    usamples::Int
    vsamples::Int
    ustep::T
    vstep::T

    function RectGrid(width::T, height::T, usamples::Int, vsamples::Int) where {T<:Real} 
        return new{T}(width, height, usamples, vsamples, width / (usamples - 1), height / (vsamples - 1))
    end
end
export RectGrid

Base.length(o::RectGrid{T}) where {T} = o.usamples * o.vsamples
Emitters.visual_size(o::RectGrid{T}) where {T} = max(o.width, o.height)

# generate origin on the agrid
function Emitters.generate(o::RectGrid{T}, n::Int) where {T<:Real}
    n = mod(n, length(o))
    v = o.vsamples == 1 ? zero(T) : 2 * Int(floor(n / o.usamples)) / (o.vsamples - 1) - 1.0
    u = o.usamples == 1 ? zero(T) : 2 * mod(n, o.usamples) / (o.usamples - 1) - 1.0
    return OpticSim.origin(T) + ((o.width / 2) * u * unitX(T)) + ((o.height/2) * v * unitY(T))
end


#-------------------------------------
# Hexapolar Origin
#-------------------------------------

# TODO: Finish this one
struct Hexapolar{T} <: AbstractOriginDistribution{T}
    halfsizeu::T
    halfsizev::T
    nrings::Int

    function Hexapolar(nrings::Int, halfsizeu::T, halfsizev::T) where {T<:Real} 
        return new{T}(halfsizeu, halfsizev, nrings)
    end
end
export Hexapolar

Base.length(o::Hexapolar{T}) where {T} = 1 + round(Int, (o.nrings * (o.nrings + 1) / 2) * 6)
Emitters.visual_size(o::Hexapolar{T}) where {T} = max(o.halfsizeu*2, o.halfsizev*2)

function Emitters.generate(o::Hexapolar{T}, n::Int) where {T<:Real}
    n = mod(n, length(o))
    if n == 0
        return OpticSim.origin(T)
    else
        t = 1
        ringi = 1
        for i in 1:(o.nrings)
            t += 6 * i
            if n < t
                ringi = i
                break
            end
        end
        ρ = ringi / o.nrings
        pind = n - (t - 6 * ringi)
        ϕ = (pind / (6 * ringi)) * 2π
        u = cos(ϕ) * o.halfsizeu
        v = sin(ϕ) * o.halfsizev
        return OpticSim.origin(T) + ρ * (u * unitX(T) + v * unitY(T))
    end
end



end # module Origins
#endregion Origins


#------------------------------------------------------------------------------
# Angular Power Distribution
#------------------------------------------------------------------------------
#region Angular Power Distribution
module AngularPower

import OpticSim
using LinearAlgebra
using ..Emitters
using ..Geometry

abstract type AbstractAngularPowerDistribution{T<:Real} end

#---------------------------------------
# Lambertian
#---------------------------------------

struct Lambertian{T} <: AbstractAngularPowerDistribution{T} 
    Lambertian(::Type{T} = Float64) where {T<:Real} = new{T}()
end

function Emitters.apply(d::Lambertian{T}, Tr::Transform{T}, power::T, ray::OpticSim.Ray{T,3}) where {T}
    return power
end
export Lambertian

#---------------------------------------
# Cosine Power Distribution
#---------------------------------------

struct Cosine{T} <: AbstractAngularPowerDistribution{T} 
    cosine_exp::T

    function Cosine(cosine_exp::T = one(T)) where {T<:Real}
        new{T}(cosine_exp)
    end
end
export Cosine

# returning ray power
function Emitters.apply(d::Cosine{T}, Tr::Transform{T}, power::T, ray::OpticSim.Ray{T,3}) where {T}
    cosanglebetween = dot(OpticSim.direction(ray), forward(Tr))
    power = power * cosanglebetween ^ d.cosine_exp
    return power
end

#---------------------------------------
# Gaussian Power Distribution
#---------------------------------------

struct Gaussian{T} <: AbstractAngularPowerDistribution{T} 
    gaussianu::T
    gaussianv::T

    function Gaussian(gaussianu::T, gaussianv::T) where {T<:Real}
        new{T}(gaussianu, gaussianv)
    end
end
export Gaussian

# returning ray power
function Emitters.apply(d::Gaussian{T}, Tr::Transform{T}, power::T, ray::OpticSim.Ray{T,3}) where {T}

    l = dot(OpticSim.direction(ray), right(Tr))
    m = dot(OpticSim.direction(ray), up(Tr))
    power = power * exp(-(d.gaussianu * l^2 + d.gaussianv * m^2))

    return power
end


end # module Angular Power
#endregion Angular Power Distribution

#------------------------------------------------------------------------------
# Sources
#------------------------------------------------------------------------------
#region Sources
module Sources

import OpticSim
using LinearAlgebra
using Distributions
using ..Emitters
using ..Geometry
using ..Spectrum
using ..Directions
using ..Origins
using ..AngularPower

abstract type AbstractSource{T<:Real} <: OpticSim.OpticalRayGenerator{T} end

Base.getindex(s::AbstractSource, index) = generate(s, index)
Base.firstindex(s::AbstractSource) = 0
Base.lastindex(s::AbstractSource) = length(s) - 1
Base.copy(a::AbstractSource) = a # most don't have any heap allocated stuff so don't really need copying


#---------------------------------------
# Source
#---------------------------------------
struct Source{  T<:Real, 
                Tr<:Transform{T},
                S<:Spectrum.AbstractSpectrum{T}, 
                O<:Origins.AbstractOriginDistribution{T}, 
                D<:Directions.AbstractDirectionDistribution{T}, 
                P<:AngularPower.AbstractAngularPowerDistribution{T}} <: AbstractSource{T}
    transform::Tr              
    spectrum::S
    origins::O
    directions::D
    power_distribution::P
    sourcenum::Int

    function Source(::Type{T} = Float64; 
        transform::Tr = Transform(), 
        spectrum::S = Spectrum.Uniform(), 
        origins::O = Origins.Point(), 
        directions::D = Directions.Constant(), 
        power::P = AngularPower.Lambertian(), 
        sourcenum::Int = 0) where {   
                Tr<:Transform,
                S<:Spectrum.AbstractSpectrum,
                O<:Origins.AbstractOriginDistribution,
                D<:Directions.AbstractDirectionDistribution,
                P<:AngularPower.AbstractAngularPowerDistribution,
                T<:Real} 
         new{T, Tr, S, O, D, P}(transform, spectrum, origins, directions, power, sourcenum)
    end

    function Source(transform::Tr, spectrum::S, origins::O, directions::D, power::P, ::Type{T} = Float64; sourcenum::Int = 0) where {   
                Tr<:Transform,
                S<:Spectrum.AbstractSpectrum,
                O<:Origins.AbstractOriginDistribution,
                D<:Directions.AbstractDirectionDistribution,
                P<:AngularPower.AbstractAngularPowerDistribution,
                T<:Real} 
         new{T, Tr, S, O, D, P}(transform, spectrum, origins, directions, power, sourcenum)
    end
end

# used to not generate new origin points if we can use last points - mainly to keep consistency of origin generation when randomness is involved
struct SourceGenerationState{T<:Real}
    n::Int
    last_index_used::Int
    last_point_generated::Vec3D{T}
end

Base.length(s::Source{T}) where {T} = length(s.origins) * length(s.directions)

function Base.iterate(s::Source{T}) where {T<:Real}
    state = SourceGenerationState(1, -1, OpticSim.origin(T))
    return iterate(s, state)
end
function Base.iterate(s::Source{T}, state::SourceGenerationState{T}) where {T<:Real}
    if (state.n > length(s))
        return nothing
    end

    return generate(s, state)
end


function Emitters.generate(s::Source{T}, n::Int) where {T<:Real}
    return generate(s, SourceGenerationState(n+1, -1, OpticSim.origin(T)))[1]
end

function Emitters.generate(s::Source{T}, state::SourceGenerationState{T} = SourceGenerationState(-1, -1, OpticSim.origin(T))) where {T<:Real}

    # @info "New State Generation"
    n::Int = state.n - 1
    origin_index = floor(Int, (n / length(s.directions))) 
    direction_index = mod(n, length(s.directions)) 

    if (origin_index == state.last_index_used)
        o = state.last_point_generated
    else
        o = generate(s.origins, origin_index)
        o = local2world(s.transform, o)
    end

    # o = generate(s.origins, origin_index)
    d = generate(s.directions, direction_index)
    
    # rotate the direction according to the orientation of the ray-originator
    d = rotate(s.transform, d)

    ray = OpticSim.Ray(o, d)
    power, wavelength = generate(s.spectrum)
    
    power = apply(s.power_distribution, s.transform, power, ray)

    # return (OpticSim.Ray(o, d), SourceGenerationState(state.n+1, origin_index, o))
    return (OpticSim.OpticalRay(ray, power, wavelength; sourcenum=s.sourcenum), SourceGenerationState(state.n+1, origin_index, o))
end

#---------------------------------------
# Composite Source
#---------------------------------------
struct CompositeSource{T} <: AbstractSource{T}
    transform::Transform{T}              
    sources::Array

    uniform_length::Int
    total_length::Int
    start_indexes::Vector{Int}

    function CompositeSource(transform::Transform{T}, sources::Array, ::Type{T} = Float64) where {T<:Real} 

        lens = [length(src) for src in sources]
        size1 = findmin(lens)[1]
        size2 = findmax(lens)[1]
        if (size1 == size2)
            uniform_length = size1
            start_indexes = Vector{Int}()
            total_length = length(sources) * uniform_length
            # @info "Uniform Length $size1 total=$total_length"
        else
            uniform_length = -1

            start_indexes = Vector{Int}()
            start = 0
            for s in sources
                push!(start_indexes, start)
                start = start + length(s)
            end
            push!(start_indexes, start)
            # @info start_indexes
            total_length = start 
        end

        new{T}(transform, sources, uniform_length, total_length, start_indexes)
    end
end

# used to not generate new origin points if we can use last points - mainly to keep consistency of origin generation when randomness is involved
# struct CompositeSourceGenerationState{T<:Real}
#     n::Int
#     last_index_used::Int
#     last_point_generated::Vec3D{T}
# end

Base.length(s::CompositeSource{T}) where {T} = s.total_length

function Base.iterate(s::CompositeSource{T}) where {T<:Real}
    state = SourceGenerationState(1, -1, OpticSim.origin(T))
    return iterate(s, state)
end
function Base.iterate(s::CompositeSource{T}, state::SourceGenerationState{T}) where {T<:Real}
    if (state.n > length(s))
        return nothing
    end

    return generate(s, state)
end

function Emitters.generate(s::CompositeSource{T}, n::Int) where {T<:Real}
    return generate(s, SourceGenerationState(n+1, -1, OpticSim.origin(T)))[1]
end

function Emitters.generate(s::CompositeSource{T}, state::SourceGenerationState{T} = SourceGenerationState(-1, -1, OpticSim.origin(T))) where {T<:Real}

    # @info "New Composite State Generation"
    n::Int = state.n - 1

    if (s.uniform_length != -1)
        source_index = floor(Int, (n / s.uniform_length)) 
        ray_index = mod(n, s.uniform_length) 
        # @info "New Composite State Generation: source=$source_index  ray=$ray_index  ($(length(s.sources)))"
    else
        n = mod(n, s.total_length)

        ## perform a binary search to find out which source can generate the spesific ray
        low = 1
        high = length(s.start_indexes) - 1    # last cell in this vector is a dummy cell containing the index after the last ray
        source_index = -1
        while (low <= high) 
            mid = floor(Int, (low + high) / 2)

            if (n < s.start_indexes[mid])
                high = mid - 1
            elseif (n >= s.start_indexes[mid+1])
                low = mid + 1
            else
                source_index = mid
                break;
            end
        end
        @assert source_index != -1
        # @info "Bin Search n=$n source_index=$source_index"
        source_index = source_index - 1 
        ray_index = n - s.start_indexes[source_index+1]
    end

    ray, new_state = generate(s.sources[source_index+1], SourceGenerationState(ray_index+1, state.last_index_used, state.last_point_generated))
    ray = s.transform * ray                 
    return (ray, SourceGenerationState(state.n+1, new_state.last_index_used, new_state.last_point_generated))

    # origin_index = floor(Int, (n / length(s.directions))) 
    # direction_index = mod(n, length(s.directions)) 

    # if (origin_index == state.last_index_used)
    #     o = state.last_point_generated
    # else
    #     o = generate(s.origins, origin_index)
    #     o = local2world(s.transform, o)
    # end

    # # o = generate(s.origins, origin_index)
    # d = generate(s.directions, direction_index)
    
    # # rotate the direction according to the orientation of the ray-originator
    # d = rotate(s.transform, d)

    # ray = OpticSim.Ray(o, d)
    # power, wavelength = generate(s.spectrum)
    
    # power = apply(s.power_distribution, s.transform, power, ray)

    # # return (OpticSim.Ray(o, d), SourceGenerationState(state.n+1, origin_index, o))
    # return (OpticSim.OpticalRay(ray, power, wavelength), SourceGenerationState(state.n+1, origin_index, o))
end

# function Emitters.generate(s::CompositeSource{T}, n::Int) where {T<:Real}
#     if (s.uniform_length != -1)
#         source_index = floor(Int, (n / s.uniform_length)) 
#         ray_index = mod(n, s.uniform_length) 
#         generate(s.sources[source_index], ray_index)
#     else
#         @error "Not implemented yet"
#     end

#     # origin_index = floor(Int, (n / length(s.directions))) 
#     # direction_index = mod(n, length(s.directions)) 

#     # o = generate(s.origins, origin_index)
#     # d = generate(s.directions, direction_index)

#     # # rotate the direction according to the orientation of the ray-originator
#     # d = rotation(s.origins) * d

#     # # rotate the direction according to the orientation of the ray-originator
#     # d = rotate(s.transform, d)

#     # ray = OpticSim.Ray(o, d)
#     # power, wavelength = generate(s.spectrum)
    
#     # power = apply(s.power_distribution, s.transform, power, ray)

#     # # return (OpticSim.Ray(o, d), SourceGenerationState(state.n+1, origin_index, o))
#     # return OpticSim.OpticalRay(ray, power, wavelength)
# end



end # module Sources
#endregion Sources

#------------------------------------------------------------------------------
# Visualization
#------------------------------------------------------------------------------
#region Visualization
module Visualization

import OpticSim
using LinearAlgebra
using Distributions
using StaticArrays

import Makie
import Makie.AbstractPlotting
import Makie.AbstractPlotting.MakieLayout

using ..Emitters
using ..Geometry
using ..Spectrum
using ..Directions
using ..Origins
using ..AngularPower
using ..Sources

const ARRROW_LENGTH = 0.5
const ARRROW_SIZE = 0.01
const MARKER_SIZE = 15


#-------------------------------------
# draw debug information - local axes and positions
#-------------------------------------
function maybe_draw_debug_info(scene::MakieLayout.LScene, o::Origins.AbstractOriginDistribution; transform::Geometry.Transform = Transform(), debug::Bool=false, kwargs...) where {T<:Real}

    dir = forward(transform)
    uv = SVector{3}(right(transform))
    vv = SVector{3}(up(transform))
    pos = OpticSim.origin(transform)

    if (debug)
        # this is a stupid hack to force makie to render in 3d - for some scenes, makie decide with no apperent reason to show in 2d instead of 3d
        AbstractPlotting.scatter!(scene, [pos[1], pos[1]+0.1], [pos[2], pos[2]+0.1], [pos[3], pos[3]+0.1], color=:red, markersize=0)

        # draw the origin and normal of the surface
        Makie.scatter!(scene, pos, color=:blue, markersize = MARKER_SIZE * visual_size(o))

        # normal
        arrow_start = pos
        arrow_end = dir * ARRROW_LENGTH * visual_size(o) 
        Makie.arrows!(scene.scene, [AbstractPlotting.Point3f0(arrow_start)], [AbstractPlotting.Point3f0(arrow_end)], arrowsize=ARRROW_SIZE * visual_size(o), arrowcolor=:blue)
        arrow_end = uv * 0.5 * ARRROW_LENGTH * visual_size(o) 
        Makie.arrows!(scene.scene, [AbstractPlotting.Point3f0(arrow_start)], [AbstractPlotting.Point3f0(arrow_end)], arrowsize= 0.5 * ARRROW_SIZE * visual_size(o), arrowcolor=:red)
        arrow_end = vv * 0.5 * ARRROW_LENGTH * visual_size(o) 
        Makie.arrows!(scene.scene, [AbstractPlotting.Point3f0(arrow_start)], [AbstractPlotting.Point3f0(arrow_end)], arrowsize= 0.5 * ARRROW_SIZE * visual_size(o), arrowcolor=:green)

        # draw all the samples origins
        positions = map(x -> local2world(transform, x), collect(o))
        positions = collect(AbstractPlotting.Point3f0, positions)
        Makie.scatter!(scene, positions, color=:green, markersize = MARKER_SIZE * visual_size(o))

        # positions = collect(AbstractPlotting.Point3f0, o)
        # Makie.scatter!(scene, positions, color=:green, markersize = MARKER_SIZE * visual_size(o))
    end

end


#-------------------------------------
# draw point origin
#-------------------------------------
# function OpticSim.Vis.draw!(scene::MakieLayout.LScene, o::Origins.Point; transform::Geometry.Transform = Transform(), kwargs...) where {T<:Real}
function OpticSim.Vis.draw!(scene::MakieLayout.LScene, o::Origins.Point; transform::Geometry.Transform = Transform(), kwargs...) where {T<:Real}
        maybe_draw_debug_info(scene, o; transform=transform, kwargs...)
end

#-------------------------------------
# draw RectGrid and RectUniform origins
#-------------------------------------
function OpticSim.Vis.draw!(scene::MakieLayout.LScene, o::Union{Origins.RectGrid, Origins.RectUniform}; transform::Geometry.Transform = Transform(), kwargs...) where {T<:Real}
    dir = forward(transform)
    uv = SVector{3}(right(transform))
    vv = SVector{3}(up(transform))
    pos = OpticSim.origin(transform)

    # @info "RECT: transform $(pos)"

    plane = OpticSim.Plane(dir, pos)
    rect = OpticSim.Rectangle(plane, o.width / 2, o.height / 2, uv, vv)
    
    OpticSim.Vis.draw!(scene, rect;  kwargs...)

    maybe_draw_debug_info(scene, o; transform=transform, kwargs...)
end


#-------------------------------------
# draw hexapolar origin
#-------------------------------------
function OpticSim.Vis.draw!(scene::MakieLayout.LScene, o::Origins.Hexapolar; transform::Geometry.Transform = Transform(), kwargs...) where {T<:Real}
    dir = forward(transform)
    uv = SVector{3}(right(transform))
    vv = SVector{3}(up(transform))
    pos = OpticSim.origin(transform)

    plane = OpticSim.Plane(dir, pos)
    ellipse = OpticSim.Ellipse(plane, o.halfsizeu, o.halfsizev, uv, vv)
    
    OpticSim.Vis.draw!(scene, ellipse;  kwargs...)

    maybe_draw_debug_info(scene, o; transform=transform, kwargs...)
end

#-------------------------------------
# draw source
#-------------------------------------
function OpticSim.Vis.draw!(scene::MakieLayout.LScene, s::Sources.Source{T}; parent_transform::Geometry.Transform = Transform(), debug::Bool=false, kwargs...) where {T<:Real}
   
    OpticSim.Vis.draw!(scene, s.origins;  transform=parent_transform * s.transform, debug=debug, kwargs...)

    if (debug)
        m = zeros(T, length(s), 7)
        for (index, optical_ray) in enumerate(s)
            ray = OpticSim.ray(optical_ray)
            ray = parent_transform * ray
            m[index, 1:7] = [ray.origin... ray.direction... OpticSim.power(optical_ray)]
        end
        
        m[:, 4:6] .*= m[:, 7] * ARRROW_LENGTH * visual_size(s.origins)  

        # Makie.arrows!(scene, [Makie.Point3f0(origin(ray))], [Makie.Point3f0(rayscale * direction(ray))]; kwargs..., arrowsize = min(0.05, rayscale * 0.05), arrowcolor = color, linecolor = color, linewidth = 2)
        color = :yellow
        Makie.arrows!(scene, m[:,1], m[:,2], m[:,3], m[:,4], m[:,5], m[:,6]; kwargs...,  arrowcolor = color, linecolor = color, linewidth = 2, arrowsize=ARRROW_SIZE * visual_size(s.origins))
    end

    # for ray in o
    #     OpticSim.Vis.draw!(scene, ray)
    # end
end

#-------------------------------------
# draw optical rays
#-------------------------------------
function OpticSim.Vis.draw!(scene::MakieLayout.LScene, rays::AbstractVector{OpticSim.OpticalRay{T, 3}}; kwargs...) where {T<:Real}
    m = zeros(T, length(rays)*2, 3)
    for (index, optical_ray) in enumerate(rays)
        ray = OpticSim.ray(optical_ray)
        m[(index-1)*2+1, 1:3] = [OpticSim.origin(optical_ray)...]
        m[(index-1)*2+2, 1:3] = [(OpticSim.origin(optical_ray) + OpticSim.direction(optical_ray) * 1 * OpticSim.power(optical_ray))... ]
    end
    
    color = :green
    Makie.linesegments!(scene, m[:,1], m[:,2], m[:,3]; kwargs...,  color = color, linewidth = 2, )
end

#-------------------------------------
# draw composite source
#-------------------------------------
function OpticSim.Vis.draw!(scene::MakieLayout.LScene, s::Sources.CompositeSource{T}; parent_transform::Geometry.Transform = Transform(), kwargs...) where {T<:Real}

    # @info "Composite"
    for source in s.sources
        # @info "Composite: local transform $(translation(s.transform))"
        # @info "Composite: child transform $(translation(source.transform))"
        OpticSim.Vis.draw!(scene, source; parent_transform=parent_transform*s.transform, kwargs...)
    end
    # OpticSim.Vis.draw!(scene, s.origins;  transform=s.transform, kwargs...)

    # m = zeros(T, length(s), 7)
    # for (index, optical_ray) in enumerate(s)
    #     ray = OpticSim.ray(optical_ray)
    #     m[index, 1:7] = [ray.origin... ray.direction... OpticSim.power(optical_ray)]
    # end
    
    # m[:, 4:6] .*= m[:, 7] * ARRROW_LENGTH * visual_size(s.origins)  

    # # Makie.arrows!(scene, [Makie.Point3f0(origin(ray))], [Makie.Point3f0(rayscale * direction(ray))]; kwargs..., arrowsize = min(0.05, rayscale * 0.05), arrowcolor = color, linecolor = color, linewidth = 2)
    # color = :yellow
    # Makie.arrows!(scene, m[:,1], m[:,2], m[:,3], m[:,4], m[:,5], m[:,6]; kwargs...,  arrowcolor = color, linecolor = color, linewidth = 2, arrowsize=ARRROW_SIZE * visual_size(s.origins))

    # # for ray in o
    # #     OpticSim.Vis.draw!(scene, ray)
    # # end
end


end # module Visualization
#endregion Visualization


# exporting stuff from the Emitters module
export Geometry, Spectrum, Directions, Origins, AngularPower, Sources

end # module Emitters

