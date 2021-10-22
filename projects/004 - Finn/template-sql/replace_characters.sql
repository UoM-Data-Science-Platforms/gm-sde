REPLACE(
    REPLACE(
        REPLACE(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            [pvt].[ACE comorbidities], CHAR(13), ' '), CHAR(10), '| '), '</p>', '|'), '<p>', ''), '</strong>', ''), '<strong>', ''), '&nbsp;', ' ') AS [ACE comorbidities]