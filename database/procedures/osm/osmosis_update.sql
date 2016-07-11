-- Drop all stored procedures if they exist.
DROP FUNCTION IF EXISTS osmosisUpdate();

-- Create stored procedures.
CREATE FUNCTION osmosisUpdate() 
RETURNS void 
AS 
$_$ 
DECLARE 
BEGIN 
END; 
$_$ 
LANGUAGE plpgsql;
