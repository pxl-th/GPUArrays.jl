import SpecialFunctions: erfc

function blackscholes(sptprice, strike, rate, volatility, time)
    logterm = log( sptprice / strike)
    powterm = .5f0 * volatility * volatility
    den = volatility * sqrt(time)
    d1 = (((rate + powterm) * time) + logterm) / den
    d2 = d1 - den
    NofXd1 = cndf2(d1)
    NofXd2 = cndf2(d2)
    futureValue = strike * exp(- rate * time)
    c1 = futureValue * NofXd2
    call_ = sptprice * NofXd1 - c1
    put  = call_ - futureValue + sptprice
    return put
end

function cndf2(x)
    0.5f0 + 0.5f0 * erfc(0.707106781f0 * x)
end

# jeeez -.- So CUDAnative still doesn't recognize e.g. sqrt in the LLVM-IR,
#since it's implemented within a C-library.... Should be fixed soon!
function cu_blackscholes(sptprice, strike, rate, volatility, time)
    logterm = cu.log(sptprice / strike)
    powterm = .5f0 * volatility * volatility
    den = volatility * cu.sqrt(time)
    d1 = (((rate + powterm) * time) + logterm) / den
    d2 = d1 - den
    NofXd1 = cu_cndf2(d1)
    NofXd2 = cu_cndf2(d2)
    futureValue = strike * cu.exp(- rate * time)
    c1 = futureValue * NofXd2
    call_ = sptprice * NofXd1 - c1
    put  = call_ - futureValue + sptprice
    return put
end

function cu_cndf2(x)
    0.5f0 + 0.5f0 * cu.erfc(0.707106781f0 * x)
end

for T in (Float32,)
    N = 1023
    sptprice   = T[42.0 for i = 1:N]
    initStrike = T[40.0 + (i / N) for i = 1:N]
    rate       = T[0.5 for i = 1:N]
    volatility = T[0.2 for i = 1:N]
    time       = T[0.5 for i = 1:N]
    result     = similar(time)
    comparison = blackscholes.(sptprice, initStrike, rate, volatility, time)
    @allbackends "Blackscholes with $T" backend begin
        _sptprice = GPUArray(sptprice)
        _initStrike = GPUArray(initStrike)
        _rate = GPUArray(rate)
        _volatility = GPUArray(volatility)
        _time = GPUArray(time)
        _result = GPUArray(result)
        blackschole_f = if backend == :cudanative
            cu_blackscholes
        else
            blackscholes
        end
        _result .= blackschole_f.(_sptprice, _initStrike, _rate, _volatility, _time)
        @test Array(_result) ≈ comparison
    end
end

@allbackends "mapidx" backend begin
    a = rand(Complex64, 1025)
    b = rand(Complex64, 1025)
    A = GPUArray(a)
    B = GPUArray(b)
    off = Cuint(1)
    mapidx(A, (B, off, Cuint(length(A)))) do i, a, b, off, len
        x = b[i]
        x2 = b[min(i+off, len)]
        a[i] = x * x2
    end
    foreach(1:length(a)) do i
        x = b[i]
        x2 = b[min(i+off, length(a))]
        a[i] = x * x2
    end
    @test Array(A) ≈ a
end


@allbackends "muladd & abs" backend begin
    a = rand(Float32, 32) - 0.5f0
    A = GPUArray(a)
    x = abs.(A)
    @test Array(x) == abs.(a)
    y = muladd.(A, 2f0, x)
    @test Array(y) == muladd(a, 2f0, abs.(a))
end
