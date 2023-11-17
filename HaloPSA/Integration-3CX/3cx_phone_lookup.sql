SELECT * 
FROM (
    SELECT
        Uid AS 'contactid',
        uFirstName AS 'firstname',
        uLastName AS 'lastname',
        aareadesc AS 'companyname',
        uemail AS 'email',
        CASE
            WHEN LEFT(REPLACE(REPLACE(REPLACE(uextn, ' ', ''), '-', ''), '/', ''), 1) = '0' 
            THEN CONCAT('+49', RIGHT(REPLACE(REPLACE(REPLACE(uextn, ' ', ''), '-', ''), '/', ''), LEN(REPLACE(REPLACE(REPLACE(uextn, ' ', ''), '-', ''), '/', '')) - 1))
            ELSE REPLACE(REPLACE(REPLACE(uextn, ' ', ''), '-', ''), '/', '')
        END AS 'phonebusiness',
        CASE
            WHEN LEFT(REPLACE(REPLACE(REPLACE(umobile2, ' ', ''), '-', ''), '/', ''), 1) = '0' 
            THEN CONCAT('+49', RIGHT(REPLACE(REPLACE(REPLACE(umobile2, ' ', ''), '-', ''), '/', ''), LEN(REPLACE(REPLACE(REPLACE(umobile2, ' ', ''), '-', ''), '/', '')) - 1))
            ELSE REPLACE(REPLACE(REPLACE(umobile2, ' ', ''), '-', ''), '/', '')
        END AS 'phonebusiness2'
    FROM users
    JOIN site ON usite = Ssitenum
    JOIN area ON aarea = sarea
) AS SubQuery
WHERE "phonebusiness" LIKE '%[Number]%'
