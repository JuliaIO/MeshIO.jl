$ NASTRAN input file for cube geometry
$ Generated from cube.stl
$ 8 nodes, 12 triangular elements
$
BEGIN BULK
$
$ Grid points (vertices) - GRID format: ID,CP,X1,X2,X3,CD,PS
GRID    1               0.0     0.0     0.0
GRID    2               0.0     0.0     10.0
GRID    3               0.0     10.0    0.0
GRID    4               0.0     10.0    10.0
GRID    5               10.0    0.0     0.0
GRID    6               10.0    0.0     10.0
GRID    7               10.0    10.0    0.0
GRID    8               10.0    10.0    10.0
$
$ Triangular shell elements - CTRIA3 format: EID,PID,G1,G2,G3
$ Face 1 (x=0 plane)
CTRIA3  1       1       2       4       1
CTRIA3  2       1       1       4       3
$ Face 2 (z=10 plane)  
CTRIA3  3       1       2       6       8
CTRIA3  4       1       4       2       8
$ Face 3 (y=0 plane)
CTRIA3  5       1       1       5       6
CTRIA3  6       1       2       1       6
$ Face 4 (z=0 plane)
CTRIA3  7       1       3       7       1
CTRIA3  8       1       1       7       5
$ Face 5 (y=10 plane)
CTRIA3  9       1       4       8       3
CTRIA3  10      1       3       8       7
$ Face 6 (x=10 plane)
CTRIA3  11      1       5       7       8
CTRIA3  12      1       6       5       8
$
ENDDATA