--!native
--!strict
local MatrixClass = {}
MatrixClass.__index = MatrixClass

local raw_constructor: (m: number, n: number, elements: {number}, immutable: boolean?) -> Matrix;
local are_inbounds: (A: Matrix, m: number, n: number) -> boolean;
local scalar_mult: (A: Matrix, b: number) -> Matrix;
local matrix_mult: (A: Matrix, B: Matrix) -> Matrix;
local num_digits: (int: number) -> number;
local bound_err_str: (A: Matrix, m: number, n: number) -> string
local immutable_err: () -> string

local identity_cache: {[number]: Matrix} = {} --caches identity matrices, key represents size (int)

local INDICES_OUT_OF_BOUNDS_ERR = "Indices out of bounds\n m: [1, %d], n: [1, %d]\nAttempted to index (m, n) = (%d, %d)";

--First order properties are immutable
export type Matrix = typeof(table.freeze(setmetatable({}:: {
	m: number;
	n: number;
	_elements: {number};
	__immutable: boolean?, --determines whether elements can be written
}, MatrixClass)))

raw_constructor = function(m: number, n: number, elements: {number}, immutable: boolean?): Matrix
	return table.freeze(
		setmetatable({
			m = m;
			n = n;
			_elements = elements;
			__immutable = immutable;
		}, MatrixClass)
	):: Matrix
end

function MatrixClass.new(rows: number, cols: number, init_elements: {number}?, immutable: boolean?): Matrix
	local elements: {number}
	if init_elements then
		if #init_elements ~= rows * cols then
			error("Initial elements of matrix does not fit within specified dimensions");
		end
		elements = table.clone(init_elements)
	else
		elements = table.create(rows * cols, 0);
	end
	return raw_constructor(rows, cols, elements, immutable):: Matrix
end

--[[Returns an n x n identity matrix, where n is an integer equal to parameter: size.
The cached copy exists, then it will return that,
]]
function MatrixClass.identity(size: number): Matrix
	
	local size: number = math.abs(size)
	if size % 1 ~= 0 then
		error("Size of identity matrix must be an integer")
	end
	
	local cached: Matrix? = identity_cache[size]
	if cached then
		return cached
	end
	
	local elements: {number} = {}
	
	for i = 1, size * size, 1 do
		local current_row: number = math.floor((i - 1) / size) + 1
		local current_column: number = i - (current_row - 1) * size
		
		local is_diagonal: boolean = current_row == current_column
		local value: number = is_diagonal and 1 or 0
		
		elements[i] = value
	end
	
	local identity_matrix: Matrix = raw_constructor(size, size, elements, true)
	identity_cache[size] = identity_matrix
	
	return identity_matrix
end

function MatrixClass.zero(rows: number, columns: number?): Matrix
	local columns: number = columns or rows
	local elements: {number} = table.create(rows * columns, 0)
	
	return raw_constructor(rows, columns, elements)
end

--returns a (3x3) rotation matrix from given CFrame
function MatrixClass.fromRotationCFrame(rot_cf: CFrame): Matrix
	local right = rot_cf.RightVector
	local up = rot_cf.UpVector
	local forward = rot_cf.LookVector
	
	return raw_constructor(3, 3, {
		right.X, up.X, forward.X,
		right.Y, up.Y, forward.Y,
		right.Z, up.Z, forward.Z
	})
end

--returns a column vector
function MatrixClass.fromArray(array: {number}): Matrix
	return raw_constructor(#array, 1, array)
end

--returns a (3x1) column vector/matrix
function MatrixClass.fromVector3(v: Vector3): Matrix
	return raw_constructor(3, 1, {
		v.X, v.Y, v.Z
	})
end

function MatrixClass.ToVector3(v: Matrix): Vector3
	if not ((v.m == 1 and v.n == 3) or (v.n == 1 and v.m == 3)) then
		error("Cannot convert matrix to Vector3, dimensions mismatched")
	end
	
	return Vector3.new(table.unpack(v._elements))
end

function MatrixClass.ToArray(self: Matrix): {number}
	return self._elements
end

-- Replaces the specified column with new values
-- @param col: Column index (1-based)
-- @param newValues: Array of numbers (must match row count)
function MatrixClass.ReplaceColumn(self: Matrix, col: number, newValues: {number}): ()
	if self.__immutable then
		error(immutable_err())
	end
	
	-- Bounds checking
	if col < 1 or col > self.n then
		error(string.format("Column index out of bounds (1-%d), got %d", self.n, col))
	end
	
	if #newValues ~= self.m then
		error(string.format("New values count must match row count (%d), got %d", self.m, #newValues))
	end

	-- Replace column elements
	for row = 1, self.m do
		local index = (row - 1) * self.n + col
		self._elements[index] = newValues[row]
	end
end

-- Replaces the specified row with new values
-- @param row: Row index (1-based)
-- @param newValues: Array of numbers (must match column count)
function MatrixClass.ReplaceRow(self: Matrix, row: number, newValues: {number}): ()
	if self.__immutable then
		error(immutable_err())
	end
	-- Bounds checking
	if row < 1 or row > self.m then
		error(string.format("Row index out of bounds (1-%d), got %d", self.m, row))
	end

	if #newValues ~= self.n then
		error(string.format("New values count must match column count (%d), got %d", self.n, #newValues))
	end

	-- Replace row elements
	local startIndex = (row - 1) * self.n + 1
	for i = 1, self.n do
		self._elements[startIndex + i - 1] = newValues[i]
	end
end

--[[Returns the element at specified row and column.
If the column-argument is ommitted then the matrix will be linearly indexed.
If last argument (new_value) and the column position are both specified, then the value at the specified position will be overwritten.
]]
function MatrixClass.__call(self: Matrix, m: number, n: number?, new_value: number?): number
	
	local index: number;
	
	if n then
		if not are_inbounds(self, m, n) then
			error(bound_err_str(self, m, n))
		end
		index = (m - 1) * self.n + n
	else
		if m > #self._elements then
			error(debug.traceback(
				"Linear index out of bounds. Attempted: "..m..", max: "..#self._elements
				));
		end
		index = m
	end
	
	local value: number = self._elements[index];
	if new_value then
		if self.__immutable then
			error(immutable_err())
		end
		self._elements[index] = new_value
	end
	
	return value;
end

--Writes value of element at specified row and column, returns old value
function MatrixClass.SetElement(self: Matrix, m: number, n: number, new_value: number): number
	return self(m, n, new_value)
end

--More explicit syntax for __call
MatrixClass.GetElement = MatrixClass.__call;

--Vector addition
function MatrixClass.__add(A: Matrix, B: Matrix): Matrix
	if A.m ~= B.m or A.n ~= B.n then
		error(debug.traceback("Cannot perform addition on matrices with different size\n"));
	end

	local new_elems: {number} = {}
	for i, v in A._elements do
		new_elems[i] = v + B._elements[i];
	end

	return raw_constructor(A.m, A.n, new_elems);
end

function MatrixClass.__unm(A: Matrix): Matrix
	local elements = {}
	for i, v in A._elements do
		elements[i] = -v
	end
	return raw_constructor(A.m, A.n, elements)
end

function MatrixClass.__sub(A: Matrix, B: Matrix): Matrix
	if A.m ~= B.m or A.n ~= B.n then
		error(debug.traceback("Cannot perform subtraction on matrices with different size\n"));
	end

	local new_elems: {number} = {}
	for i, v in A._elements do
		new_elems[i] = v - B._elements[i];
	end

	return raw_constructor(A.m, A.n, new_elems);
end

function MatrixClass.__mul(A: Matrix, B: number | Vector3 | Matrix): Matrix
	local a_type: string = type(A)
	local b_type: string = type(B)
	if a_type == "table" and b_type == "table" then
		return matrix_mult(A, B:: Matrix)
	end
	
	if b_type == "table" then --swap
		local temp: Matrix = B:: Matrix
		B = A
		A = temp
		
		b_type = a_type
		a_type = "table"
	end
	
	if b_type == "number" then
		
		return scalar_mult(A, B:: number)
		
	elseif typeof(B) == "Vector3" then
		
		local v: Matrix = MatrixClass.fromVector3(B)
		return matrix_mult(A, v)
	end
	
	return matrix_mult(A, B:: Matrix);
end

function MatrixClass.__eq(A: Matrix, B: Matrix): boolean
	if A.m ~= B.m or A.n ~= B.n then
		return false
	end
	
	for i, v in A._elements do
		if v ~= B[i] then
			return false
		end
	end
	
	return true
end

function MatrixClass.__tostring(self: Matrix): string
	local result = "Matrix:\n{";
	
	local max_digits = num_digits(math.max(table.unpack(self._elements)));
	local format_normal_int: string = "%"..tostring(max_digits).."d, ";
	local format_normal_float: string = "%.3f, ";
	local format_newline: string = "\n	"
	
	for i, v in self._elements do
		
		local is_int: boolean = (v % 1 == 0)
		local format_normal: string = is_int and format_normal_int or format_normal_float
		
		local on_last_column: boolean = ((i - 1) % self.n == 0)
		local format: string = on_last_column and format_newline..format_normal or format_normal
		
		result = result .. format:format(v)
	end
	result = result.."\n}";

	return result;
end

scalar_mult = function(A: Matrix, b: number): Matrix
	local elems = {}
	for i, v in A._elements do
		elems[i] = v * b;
	end
	return raw_constructor(A.m, A.n, elems)
end

matrix_mult = function(A: Matrix, B: Matrix): Matrix
	if A.n ~= B.m then
		error(debug.traceback(`Matrix multiplication dimensions mismatched, A: ({A.m}, {A.n}) B: ({B.m}, {B.n})`))
	end

	local elems: {number} = {};

	local new_m, new_n = A.m, B.n;

	for m = 1, A.m do
		for n = 1, B.n do
			local dot = 0;
			for k = 1, A.n do --could also be B.m
				dot += A(m, k) * B(k, n);
			end

			local index = (m - 1) * new_n + n;
			elems[index] = dot;
		end
	end

	return raw_constructor(new_m, new_n, elems)
end

-- Returns a transposed copy of the original matrix
function MatrixClass.Transpose(self: Matrix): Matrix
	local new_elems = table.create(self.m * self.n, 0)

	for m = 1, self.m do
		for n = 1, self.n do
			local new_index = (n - 1) * self.m + m
			new_elems[new_index] = self(m, n)
		end
	end

	return raw_constructor(self.n, self.m, new_elems)
end

-- Helper function to check if a number is effectively zero (to avoid division by near-zero)
local function IsZero(value: number, epsilon: number?): boolean
	local epsilon: number = epsilon or 1e-10
	return math.abs(value) < epsilon
end

-- Helper function to perform partial pivoting
local function partialPivot(A: Matrix, B: Matrix, row: number, pivot: number): ()
	local max_row = row
	local max_val = math.abs(A(row, pivot))

	for i = row + 1, A.m do
		if math.abs(A(i, pivot)) > max_val then
			max_val = math.abs(A(i, pivot))
			max_row = i
		end
	end

	if max_row ~= row then
		-- Swap rows in A
		for col = 1, A.n do
			local temp = A(row, col)
			A:SetElement(row, col, A(max_row, col))
			A:SetElement(max_row, col, temp)
		end

		-- Swap corresponding rows in B
		for col = 1, B.n do
			local temp = B(row, col)
			B:SetElement(row, col, B(max_row, col))
			B:SetElement(max_row, col, temp)
		end
	end
end

-- Solves a linear system Ax = B using Gaussian elimination with partial pivoting
function MatrixClass.SolveLinearSystem(A: Matrix, B: Matrix): Matrix?
	-- Check dimensions
	if A.m ~= A.n then
		warn("Matrix A must be square for SolveLinearSystem")
		return nil
	end

	if B.m ~= A.m then
		warn("Matrix B row count must match Matrix A dimension")
		return nil
	end

	-- Create copies to avoid modifying originals
	local A_copy = raw_constructor(A.m, A.n, table.clone(A._elements))
	local B_copy = raw_constructor(B.m, B.n, table.clone(B._elements))

	-- Forward elimination with partial pivoting
	for pivot = 1, A_copy.m - 1 do
		partialPivot(A_copy, B_copy, pivot, pivot)

		if IsZero(A_copy(pivot, pivot)) then
			warn("Matrix is singular or nearly singular")
			return nil
		end

		for row = pivot + 1, A_copy.m do
			local factor = A_copy(row, pivot) / A_copy(pivot, pivot)

			for col = pivot, A_copy.n do
				A_copy:SetElement(row, col, A_copy(row, col) - factor * A_copy(pivot, col))
			end

			for col = 1, B_copy.n do
				B_copy:SetElement(row, col, B_copy(row, col) - factor * B_copy(pivot, col))
			end
		end
	end

	-- Back substitution
	local X = MatrixClass.new(A_copy.n, B_copy.n)

	for col = 1, B_copy.n do
		for row = A_copy.m, 1, -1 do
			local sum = 0

			for i = row + 1, A_copy.n do
				sum = sum + A_copy(row, i) * X(i, col)
			end

			if IsZero(A_copy(row, row)) then
				warn("Matrix is singular or nearly singular")
				return nil
			end

			X:SetElement(row, col, (B_copy(row, col) - sum) / A_copy(row, row))
		end
	end

	return X
end

-- Computes the least squares solution to Ax = B
function MatrixClass.FastLeastSquares(A: Matrix, B: Matrix, lambda: number?): Matrix
	local lambda: number = lambda or 1e-7  -- Tiny default regularization to avoid singularity

	local AT = A:Transpose()
	local ATA = AT * A
	local ATB = AT * B

	-- Add lambda * I to diagonal of ATA to ensure invertibility
	for i = 1, math.min(ATA.m, ATA.n) do
		ATA:SetElement(i, i, ATA(i, i) + lambda)
	end

	-- Solve (AᵀA + λI)x = AᵀB
	local solution = MatrixClass.SolveLinearSystem(ATA, ATB)
	return solution or MatrixClass.new(A.n, B.n)  -- Fallback (shouldn't happen with lambda > 0)
end

are_inbounds = function(A: Matrix, m: number, n: number): boolean
	return m > 0 and m <= A.m and n > 0 and n <= A.n;
end

num_digits = function(int: number): number
	local count = 0;
	int += 1;

	while int > 0 do
		int = math.floor(int / 10);
		count += 1;
	end

	return count;
end

bound_err_str = function(A: Matrix, m: number, n: number): string
	return debug.traceback(
		string.format(INDICES_OUT_OF_BOUNDS_ERR, A.m, A.n, m, n)
	);
end

immutable_err = function(): string
	return debug.traceback(
		"The elements of this matrix have been set to immutable"
	)
end

return MatrixClass
