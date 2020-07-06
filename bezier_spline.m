function [R] = bezier_spline(P,u)
%WRITTEN BY LUKAS BADUM, APRIL 2020.
%l.badum@web.de
%FOR THEORETIC BACKGROUND, SEE:
%Casey, M. V. "A computational geometry for the blades and internal flow channels of centrifugal compressors." (1983): 288-295.

%Bezier spline function to calculate the coordinates of point R, which lies
%on the Bezier spline defined by the points P.
%P is a construction point matrix with n * d elements.
%n is the number of points, d is the number of dimensions (eg. 2 for 2d
%planar coordinate system).
%P = [x11 x21 ... x1n; ...; xn1 ... xnd];
%u is a number between 0 and 1 which gives back the position of R on the
%spline defined by the construction points P. For convenience, u can also
%be a vector to calculate several points R.
%if u(i) = 0, R(i) = P(:,1) and if u(i) = 1, R = P(:,end).
%The coordinates of  point R are calculated using the construction points
%and a weighting function according to Bezier spline definition:
% R = sum_(k=0)^n * P_k *(n over k) * u^k * (1-u)^(n-k)

%define variables:
%number of dimensions:
d = size(P,1);
%dpolynomial degree of the Bezier spline:
n = size(P,2)-1;
%vector for number of point identities:
k_vector = 0:1:n;
R=[];
%calculate resulting spline points for u; u can be scalar or vector.
for i=1:length(u)
    %calculating the weighting function vector:
    B_vector = (factorial(n)./(factorial(k_vector).*factorial(n-k_vector))) .* u(i).^k_vector.*(1-u(i)).^(n-k_vector);
    %resulting coordinate for output point on bezier spline:
    R(:,i) =(sum( (P.*B_vector)'))';
end
% Plot if necessary:
% plot(P(1,:),P(2,:),'*--');hold on;plot(R(1,:),R(2,:));
end

