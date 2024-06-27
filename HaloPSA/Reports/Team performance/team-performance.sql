SELECT 
    uname AS [Agent Name], 
    COALESCE((SELECT ROUND(SUM(TimeTaken), 2) 
              FROM Actions 
              WHERE WhoAgentID = UNum 
              AND whe_ BETWEEN @startdate AND @enddate), 0) AS [Time Logged],
    (SELECT COUNT(*) 
     FROM actions 
     WHERE who=uname 
     AND (actoutcome LIKE 'Opened' OR actoutcome LIKE '%Geöffnet%') 
     AND whe_>@startdate 
     AND whe_<@enddate) AS [Opened Tickets],
    (SELECT COUNT(faultid) 
     FROM Faults 
     WHERE ClearWhoInt=unum 
     AND status=9 
     AND datecleared>@startdate 
     AND datecleared<@enddate) AS [Closed Tickets],
    (SELECT COUNT(*) 
     FROM actions 
     WHERE who=uname 
     AND (actoutcome NOT LIKE '%Open%' 
          AND actoutcome NOT LIKE '%Geöffnet%' 
          AND actoutcome NOT LIKE '%Close%' 
          AND actoutcome NOT LIKE '%Geschlossen%'
          AND actoutcome NOT LIKE 'Changed Status' 
          AND actoutcome NOT LIKE 'Changed Priority' 
          AND actoutcome NOT LIKE '%Respond%' 
          AND actoutcome NOT LIKE 'User Changed') 
     AND whe_>@startdate 
     AND whe_<@enddate) AS [Actions],
    COALESCE((SELECT SUM(IIF(FBScore IN (1, 2), 1, 0)) 
              FROM Feedback 
              INNER JOIN Faults ON FBFaultID = FaultID 
              WHERE ClearWhoInt = UNum 
              AND FBDate BETWEEN @startdate AND @enddate), 0) AS [Positive Feedback],
    COALESCE((SELECT SUM(IIF(FBScore IN (4), 1, 0)) 
              FROM Feedback 
              INNER JOIN Faults ON FBFaultID = FaultID 
              WHERE ClearWhoInt = UNum 
              AND FBDate BETWEEN @startdate AND @enddate), 0) AS [Negative Feedback],
    ROUND(COALESCE((SELECT ROUND(SUM(TimeTaken), 2) * 2 
              FROM Actions 
              WHERE WhoAgentID = UNum 
              AND whe_ BETWEEN @startdate AND @enddate), 0) 
    + (SELECT COUNT(*) 
       FROM actions 
       WHERE who=uname 
       AND (actoutcome LIKE 'Opened' OR actoutcome LIKE '%Geöffnet%') 
       AND whe_>@startdate 
       AND whe_<@enddate)
    + (SELECT COUNT(faultid) * COALESCE(cfbonuspointsmultiplier, 1)
       FROM Faults 
       WHERE ClearWhoInt=unum 
       AND status=9 
       AND datecleared>@startdate 
       AND datecleared<@enddate)
    + (SELECT COUNT(*) * 0.7
       FROM actions 
       WHERE who=uname 
       AND (actoutcome NOT LIKE '%Open%' 
            AND actoutcome NOT LIKE '%Geöffnet%' 
            AND actoutcome NOT LIKE '%Close%' 
            AND actoutcome NOT LIKE '%Geschlossen%'
            AND actoutcome NOT LIKE 'Changed Status' 
            AND actoutcome NOT LIKE 'Changed Priority' 
            AND actoutcome NOT LIKE '%Respond%' 
            AND actoutcome NOT LIKE 'User Changed') 
       AND whe_>@startdate 
       AND whe_<@enddate)
   + COALESCE((SELECT SUM(IIF(FBScore IN (1, 2), 1, 0)) 
              FROM Feedback 
              INNER JOIN Faults ON FBFaultID = FaultID 
              WHERE ClearWhoInt = UNum 
              AND FBDate BETWEEN @startdate AND @enddate) * 4, 0)
   + COALESCE((SELECT SUM(IIF(FBScore IN (4), 1, 0)) 
      FROM Feedback 
      INNER JOIN Faults ON FBFaultID = FaultID 
      WHERE ClearWhoInt = UNum 
      AND FBDate BETWEEN @startdate AND @enddate) * -5, 0)
   + COALESCE((SELECT ROUND(SUM(TimeTaken * 1.5), 2)
              FROM Actions 
              WHERE WhoAgentID = UNum 
              AND whe_ BETWEEN @startdate AND @enddate), 0)
     , 2) AS [TORU-Score®]
FROM UNAME
WHERE Unum NOT IN (1, 23, 17, 3, 6, 5, 20, 14, 27, 9) 
AND Uisdisabled=0
GROUP BY uname, unum, cfbonuspointsmultiplier
