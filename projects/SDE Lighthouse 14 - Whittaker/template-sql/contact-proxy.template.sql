--┌────────────────────────────────────┐
--│ LH004 GP Contact Proxy             │
--└────────────────────────────────────┘

SELECT
    "GmPseudo"
    , "FK_Patient_ID"
    , "EventDate"
    , "Contact"
    , "FaceToFace_Coded"
    , "Telephone_Coded"
    , "VideoConsultation_Coded"
FROM PRESENTATION.GP_RECORD."Contacts_Proxy_Detail_SecondaryUses"