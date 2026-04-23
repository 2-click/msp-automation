SELECT * FROM (
    SELECT
        u.Uid AS contactid,
        CASE WHEN n.gen=1 THEN '' ELSE u.uFirstName END AS firstname,
        CASE WHEN n.gen=1 THEN '' ELSE u.uLastName  END AS lastname,
        a.aareadesc AS companyname,
        u.uemail AS email,
        CASE WHEN LEFT(n.ext,1)='0' THEN '+49'+SUBSTRING(n.ext,2,50) ELSE n.ext END AS phonebusiness,
        CASE WHEN LEFT(n.m2, 1)='0' THEN '+49'+SUBSTRING(n.m2, 2,50) ELSE n.m2  END AS phonebusiness2,
        CASE WHEN LEFT(n.m1, 1)='0' THEN '+49'+SUBSTRING(n.m1, 2,50) ELSE n.m1  END AS phonemobile,
        CASE WHEN LEFT(n.hm, 1)='0' THEN '+49'+SUBSTRING(n.hm, 2,50) ELSE n.hm  END AS phonehome
    FROM users u
    JOIN site s ON u.usite = s.Ssitenum
    JOIN area a ON a.Aarea = s.sarea
    CROSS APPLY (SELECT
        REPLACE(REPLACE(REPLACE(ISNULL(u.uextn,   ''),' ',''),'-',''),'/','') AS ext,
        REPLACE(REPLACE(REPLACE(ISNULL(u.umobile, ''),' ',''),'-',''),'/','') AS m1,
        REPLACE(REPLACE(REPLACE(ISNULL(u.umobile2,''),' ',''),'-',''),'/','') AS m2,
        REPLACE(REPLACE(REPLACE(ISNULL(u.utelhome,''),' ',''),'-',''),'/','') AS hm,
        CASE WHEN u.uFirstName='Allgemeiner' AND u.uLastName='Benutzer' THEN 1 ELSE 0 END AS gen
    ) n
) AS SubQuery
WHERE (DATALENGTH(phonebusiness)  > 0
    OR DATALENGTH(phonebusiness2) > 0
    OR DATALENGTH(phonemobile)    > 0
    OR DATALENGTH(phonehome)      > 0)
  AND (firstname      LIKE '%[SearchText]%'
    OR lastname       LIKE '%[SearchText]%'
    OR companyname    LIKE '%[SearchText]%'
    OR phonebusiness  LIKE '%[SearchText]%'
    OR phonebusiness2 LIKE '%[SearchText]%'
    OR phonemobile    LIKE '%[SearchText]%'
    OR phonehome      LIKE '%[SearchText]%')
