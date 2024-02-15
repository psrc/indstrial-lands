/* Gross Inventory spatial queries - acreage */

--2023 Inventory

    UPDATE Sandbox.Mike.ili20231221_net
    SET Shape = Shape.MakeValid();
    GO

    WITH cte AS(SELECT c.county_nm, i.ind_type, round(sum(c.Shape.STDifference(w.Shape).STIntersection(i.Shape).STArea())/43560,2) AS acres
                FROM ElmerGeo.dbo.COUNTY_BACKGROUND AS c JOIN Sandbox.Mike.ili20231221 AS i ON 1=1  LEFT JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1
                WHERE c.county_fip IN('033','035','053','061')
                GROUP BY c.county_nm, i.ind_type)
    SELECT * FROM cte PIVOT (max(acres) FOR ind_type IN([Core Industrial], [Industrial-Commercial], [Aviation Operations], [Military Industrial], [Limited Industrial])) AS p;

    WITH cte AS(SELECT CASE WHEN i.ind_type IS NOT NULL THEN i.ind_type ELSE 'Non-Industrial' END AS ind_type, m.mic, round(sum(m.Shape.STDifference(w.Shape).STIntersection(i.Shape).STArea())/43560,2) AS acres
                FROM ElmerGeo.dbo.MICEN AS m LEFT JOIN Sandbox.Mike.ili20231221 AS i ON 1=1 LEFT JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1
                WHERE m.mic IS NOT NULL
                GROUP BY CASE WHEN i.ind_type IS NOT NULL THEN i.ind_type ELSE 'Non-Industrial' END, m.mic)
    SELECT * FROM cte PIVOT (max(acres) FOR ind_type IN([Core Industrial], [Industrial-Commercial], [Aviation Operations], [Military Industrial], [Limited Industrial], [Non-Industrial])) AS p;

    SELECT m.mic, w.objectid, m.Shape.STDifference(w.Shape).STArea()/43560 AS acres
    FROM ElmerGeo.dbo.MICEN AS m LEFT JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1 WHERE m.mic IS NOT NULL AND w.OBJECTID<>1
    ORDER BY m.mic, w.objectid;

    SELECT m.mic, m.Shape.STArea()/43560 AS acres
    FROM ElmerGeo.dbo.MICEN AS m WHERE m.mic IS NOT NULL
    ORDER BY m.mic;

--2015 Inventory

    WITH cte AS(SELECT i.segment, c.county_nm, round(sum(c.Shape.STDifference(w.Shape).STIntersection(i.Shape).STArea())/43560,2) AS acres
                FROM ElmerGeo.dbo.COUNTY_BACKGROUND AS c LEFT JOIN Sandbox.Mike.ili_2015 AS i ON 1=1 JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1
                WHERE c.county_fip IN('033','035','053','061')
                GROUP BY i.segment, c.county_nm)
    SELECT * FROM cte PIVOT (max(acres) FOR segment IN([Core Industrial], [Industrial-Commercial], [Aviation Operations], [Military])) AS p;

    WITH cte AS(SELECT CASE WHEN i.segment IS NOT NULL THEN i.segment ELSE 'Non-Industrial' END as segment, m.mic, round(sum(m.Shape.STDifference(w.Shape).STIntersection(i.Shape).STArea())/43560,2) AS acres
                FROM ElmerGeo.dbo.MICEN AS m LEFT JOIN Sandbox.Mike.ili_2015 AS i ON 1=1 JOIN ElmerGeo.dbo.LARGEST_WATERBODIES AS w ON 1=1
                WHERE m.mic IS NOT NULL
                GROUP BY CASE WHEN i.segment IS NOT NULL THEN i.segment ELSE 'Non-Industrial'  END, m.mic)
    SELECT * FROM cte PIVOT (max(acres) FOR segment IN([Core Industrial], [Industrial-Commercial], [Aviation Operations], [Military], [Non-Industrial])) AS p;

    SELECT m.mic, round(sum(m.Shape.STArea())/43560,2) FROM ElmerGeo.dbo.MICEN AS m GROUP BY m.mic
