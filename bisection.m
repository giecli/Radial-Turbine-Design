
function p = bisection(f,a,b,r)
% provide the equation you want to solve with R.H.S = 0 form.
% Write the L.H.S by using inline function
% Give initial guesses.
% Solves it by method of bisection.
% A very simple code. But may come handy
% provide f in the form of: f= @(x) (x^2)-2*x-2;
% residual r
counter=0;
if f(a)*f(b)>0
    disp('wrong initial choice in bisection method algorithm')
    p=[];
else
    p = (a + b)/2;
    err = abs(f(p));
    while err > r&counter<10
        if f(a)*f(p)<0
            b = p;
        else
            a = p;
        end
        p = (a + b)/2 ;
        err = abs(f(p));
        counter=counter+1;
    end
end
end