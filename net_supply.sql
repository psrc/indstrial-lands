DROP TABLE IF EXISTS Sandbox.Mike.ilx_all_ind_parcels;
GO
CREATE TABLE Sandbox.Mike.ilx_indprcl_all(parcel_id int PRIMARY KEY NOT NULL, 
                                          ind_type nvarchar(25), 
                                          county_id smallint, 
                                          mic nvarchar(40), 
                                          impval int, 
                                          gross_sqft int, 
                                          land_use_type_id smallint,
                                          net_flag nchar(1), 
                                          Shape geometry,
                                          CentroidShape geometry);
GO 
INSERT INTO Sandbox.Mike.ilx_indprcl_all(parcel_id, Shape, CentroidShape)
SELECT p.OBJECTID AS parcel_id, p.Shape, p.Shape.STCentroid()
FROM ElmerGeo.dbo.PARCELS_URBANSIM_2018 AS p;
GO
CREATE SPATIAL INDEX ilxs_all_ind_parcels ON Sandbox.Mike.ilx_indprcl_all(CentroidShape)  
USING GEOMETRY_AUTO_GRID WITH (BOUNDING_BOX = (xmin = 1111000, ymin = -92400, xmax = 1520420, ymax = 476385));
GO
UPDATE x
SET x.ind_type=i.indtype 
FROM Sandbox.Mike.ilx_indprcl_all AS x JOIN Sandbox.Mike.ili_20230808 AS i ON x.CentroidShape.STIntersects(i.Shape)=1 AND i.indtype IN('Airport Operations');
GO
DELETE FROM Sandbox.Mike.ilx_indprcl_all WHERE ind_type IS NULL;
GO
UPDATE x
SET x.impval=i.imp_val,
    x.gross_sqft=i.gross_sqft,
    x.land_use_type_id=i.land_use_type_id
FROM Sandbox.Mike.ilx_indprcl_all AS x JOIN Sandbox.Mike.ilx_impval_all AS i ON x.parcel_id=i.parcel_id;
GO
UPDATE Sandbox.Mike.ilx_indprcl_all
SET net_flag=CASE WHEN impval IS NULL OR impval/gross_sqft < 0.01 THEN 'v' WHEN impval/gross_sqft < 5.35 THEN 'r' ELSE '' END;
GO
UPDATE x 
SET x.county_id=CAST(county_fip AS smallint)
FROM Sandbox.Mike.ilx_indprcl_all AS x JOIN ElmerGeo.dbo.COUNTY_BACKGROUND AS c ON x.CentroidShape.STIntersects(c.Shape)=1;
GO
UPDATE x 
SET x.mic=m.mic
FROM Sandbox.Mike.ilx_indprcl_all AS x JOIN ElmerGeo.dbo.MICEN AS m ON x.CentroidShape.STIntersects(m.Shape)=1;

SELECT x.mic, x.net_flag, sum(x.gross_sqft*.9/43560) AS acres FROM Sandbox.Mike.ilx_indprcl_all AS x
WHERE x.net_flag <>'' AND x.land_use_type_id NOT IN(2,6,7,8,19,22,23,29)  AND x.ind_type NOT IN('Airport Operations','Military') 
--AND NOT EXISTS (SELECT 1 FROM Sandbox.Mike.ilx_lockouts AS l WHERE l.parcel_id=x.parcel_id)
GROUP BY x.net_flag, x.mic ORDER BY x.net_flag, x.mic;

SELECT x.county_id, x.net_flag, sum(x.gross_sqft*.9/43560) AS acres FROM Sandbox.Mike.ilx_indprcl_all AS x  
WHERE x.net_flag <>'' AND x.land_use_type_id NOT IN(2,6,7,8,19,22,23,29)  AND x.ind_type NOT IN('Airport Operations','Military')
--AND NOT EXISTS (SELECT 1 FROM Sandbox.Mike.ilx_lockouts AS l WHERE l.parcel_id=x.parcel_id)
GROUP BY x.net_flag, x.county_id ORDER BY x.net_flag, x.county_id;

SELECT x.ind_type, x.net_flag, sum(x.gross_sqft*.9/43560) AS acres FROM Sandbox.Mike.ilx_indprcl_all AS x 
WHERE x.net_flag <>'' AND x.land_use_type_id NOT IN(2,6,7,8,19,22,23,29)  AND x.ind_type NOT IN('Airport Operations','Military')
--AND NOT EXISTS (SELECT 1 FROM Sandbox.Mike.ilx_lockouts AS l WHERE l.parcel_id=x.parcel_id)
GROUP BY x.net_flag, x.ind_type ORDER BY x.net_flag, x.ind_type;

SELECT x.county_id, x.net_flag, sum(x.gross_sqft*.9/43560) AS acres FROM Sandbox.Mike.ilx_indprcl_all AS x 
WHERE x.net_flag <>'' AND x.land_use_type_id NOT IN(2,6,7,8,19,22,23,29)  AND x.ind_type ='Mixed-use'
--AND NOT EXISTS (SELECT 1 FROM Sandbox.Mike.ilx_lockouts AS l WHERE l.parcel_id=x.parcel_id)
GROUP BY x.net_flag, x.county_id ORDER BY x.net_flag, x.county_id;

DROP TABLE IF EXISTS Sandbox.Mike.ilx_net;
GO
SELECT parcel_id, ind_type, mic, impval, gross_sqft, land_use_type_id, net_flag, Shape 
INTO Sandbox.Mike.ilx_net
FROM Sandbox.Mike.ilx_indprcl_all
WHERE net_flag <>'' AND land_use_type_id NOT IN(2,6,7,8,19,22,23,29)  AND ind_type NOT IN('Airport Operations','Military')



