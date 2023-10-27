
WITH cte AS(SELECT i.ind_type, m.mic, 
            round(sum(m.Shape.STDifference(w.Shape).STIntersection(i.Shape).STArea())/43560,2) AS acres
            FROM ElmerGeo.dbo.MICEN AS m LEFT JOIN Sandbox.Mike.ili20231023 AS i ON 1=1 LEFT JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1
            GROUP BY i.ind_type, m.mic)
SELECT * FROM cte PIVOT (max(acres) FOR ind_type IN([Core Industrial], [Industrial-Commercial], [Aviation Operations], [Military Industrial], [Limited Industrial])) AS p;

SELECT m.mic, m.Shape.STArea()/43560 AS acres
FROM ElmerGeo.dbo.MICEN AS m WHERE m.mic IS NOT NULL
ORDER BY m.mic;

SELECT m.mic, w.objectid, m.Shape.STDifference(w.Shape).STArea()/43560 AS acres
FROM ElmerGeo.dbo.MICEN AS m LEFT JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1 WHERE m.mic IS NOT NULL AND w.OBJECTID<>1
ORDER BY m.mic, w.objectid;

WITH cte AS(
    SELECT c.county_nm, i.ind_type, round(sum(c.Shape.STDifference(w.Shape).STIntersection(i.Shape).STArea())/43560,2) AS acres
    FROM ElmerGeo.dbo.COUNTY_BACKGROUND AS c JOIN Sandbox.Mike.ili20231023 AS i ON 1=1  LEFT JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1
    WHERE c.county_fip IN('033','035','053','061')
    GROUP BY c.county_nm, i.ind_type)
SELECT * FROM cte PIVOT (max(acres) FOR ind_type IN([Core Industrial], [Industrial-Commercial], [Aviation Operations], [Military Industrial], [Limited Industrial])) AS p;