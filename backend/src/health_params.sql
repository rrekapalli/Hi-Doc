INSERT INTO param_targets (param_code, target_min, target_max, preferred_unit, description, notes, organ_system) VALUES
-- General Vitals
('BMI', 18.5, 24.9, 'kg/m²', 'Body Mass Index', 'Healthy adult range', 'General'),
('BP_SYS', 90, 120, 'mmHg', 'Systolic Blood Pressure', 'Resting measurement', 'Cardiovascular'),
('BP_DIA', 60, 80, 'mmHg', 'Diastolic Blood Pressure', 'Resting measurement', 'Cardiovascular'),
('HR', 60, 100, 'bpm', 'Resting Heart Rate', 'Adults at rest', 'Cardiovascular'),
('RESP_RATE', 12, 20, 'breaths/min', 'Respiratory Rate', 'Adults at rest', 'Respiratory'),
('TEMP', 36.5, 37.5, '°C', 'Body Temperature', 'Core temperature', 'General'),

-- CBC
('WBC', 4.0, 11.0, 'x10^9/L', 'White Blood Cell Count', 'Leukocytes in blood', 'Immune/Hematology'),
('RBC', 4.2, 6.1, 'x10^12/L', 'Red Blood Cell Count', 'Number of erythrocytes', 'Hematology'),
('HGB', 13.5, 17.5, 'g/dL', 'Hemoglobin', 'Oxygen-carrying protein', 'Hematology'),
('HCT', 38.8, 50.0, '%', 'Hematocrit', 'Proportion of red blood cells', 'Hematology'),
('PLT', 150, 450, 'x10^9/L', 'Platelet Count', 'Blood clotting cells', 'Hematology'),
('MCV', 80, 96, 'fL', 'Mean Corpuscular Volume', 'Average RBC size', 'Hematology'),
('MCH', 27, 33, 'pg', 'Mean Corpuscular Hemoglobin', 'Hemoglobin per RBC', 'Hematology'),
('MCHC', 32, 36, 'g/dL', 'Mean Corpuscular Hemoglobin Concentration', 'Hemoglobin concentration in RBCs', 'Hematology'),

-- Basic Metabolic Panel
('GLU_FAST', 70, 100, 'mg/dL', 'Fasting Blood Glucose', '8–12 hours fasting', 'Metabolic'),
('BUN', 7, 20, 'mg/dL', 'Blood Urea Nitrogen', 'Kidney function indicator', 'Renal'),
('CREAT', 0.6, 1.3, 'mg/dL', 'Creatinine', 'Renal function marker', 'Renal'),
('NA', 135, 145, 'mmol/L', 'Sodium', 'Electrolyte balance', 'Metabolic'),
('K', 3.5, 5.0, 'mmol/L', 'Potassium', 'Electrolyte balance', 'Metabolic'),
('CL', 98, 106, 'mmol/L', 'Chloride', 'Electrolyte balance', 'Metabolic'),
('CO2', 23, 29, 'mmol/L', 'Bicarbonate', 'Acid-base balance', 'Metabolic'),
('CA', 8.6, 10.2, 'mg/dL', 'Calcium', 'Bone & muscle function', 'Metabolic'),
('PHOS', 2.5, 4.5, 'mg/dL', 'Phosphate', 'Bone & metabolic function', 'Metabolic'),
('MG', 1.7, 2.2, 'mg/dL', 'Magnesium', 'Enzyme & nerve function', 'Metabolic'),

-- Liver Function
('ALT', 7, 55, 'U/L', 'Alanine Aminotransferase', 'Liver enzyme', 'Liver'),
('AST', 8, 48, 'U/L', 'Aspartate Aminotransferase', 'Liver enzyme', 'Liver'),
('ALP', 44, 147, 'U/L', 'Alkaline Phosphatase', 'Bile duct & bone health', 'Liver'),
('BILITOT', 0.1, 1.2, 'mg/dL', 'Total Bilirubin', 'Liver & hemolysis marker', 'Liver'),
('BILIDIR', 0, 0.3, 'mg/dL', 'Direct Bilirubin', 'Conjugated bilirubin', 'Liver'),
('ALB', 3.4, 5.4, 'g/dL', 'Albumin', 'Liver synthetic function', 'Liver'),
('GGT', 9, 48, 'U/L', 'Gamma-Glutamyl Transferase', 'Liver & bile duct marker', 'Liver'),

-- Lipid Profile
('TC', 125, 200, 'mg/dL', 'Total Cholesterol', 'Desirable range', 'Cardiovascular'),
('LDL', 0, 100, 'mg/dL', 'Low-Density Lipoprotein', 'Bad cholesterol', 'Cardiovascular'),
('HDL', 40, 60, 'mg/dL', 'High-Density Lipoprotein', 'Good cholesterol', 'Cardiovascular'),
('TG', 0, 150, 'mg/dL', 'Triglycerides', 'Fat in blood', 'Cardiovascular'),

-- Diabetes
('HBA1C', 4.0, 5.6, '%', 'Hemoglobin A1c', '3-month average glucose', 'Metabolic'),
('FRUCTOSAMINE', 175, 280, 'µmol/L', 'Fructosamine', '2–3 week glucose control', 'Metabolic'),

-- Cardiac Markers
('TROPONIN_T', 0, 0.04, 'ng/mL', 'Troponin T', 'Heart attack marker', 'Cardiovascular'),
('TROPONIN_I', 0, 0.04, 'ng/mL', 'Troponin I', 'Heart injury marker', 'Cardiovascular'),
('CK_TOTAL', 20, 200, 'U/L', 'Creatine Kinase Total', 'Muscle breakdown', 'Musculoskeletal'),
('CK_MB', 0, 5, 'ng/mL', 'Creatine Kinase-MB', 'Cardiac injury indicator', 'Cardiovascular'),
('BNP', 0, 100, 'pg/mL', 'B-type Natriuretic Peptide', 'Heart failure marker', 'Cardiovascular'),
('NT_PROBNP', 0, 125, 'pg/mL', 'N-terminal proBNP', 'Heart failure marker', 'Cardiovascular'),

-- Inflammation & Immune
('ESR', 0, 20, 'mm/hr', 'Erythrocyte Sedimentation Rate', 'Inflammation indicator', 'Immune'),
('CRP', 0, 3, 'mg/L', 'C-Reactive Protein', 'Acute inflammation marker', 'Immune'),
('PROCAL', 0, 0.1, 'ng/mL', 'Procalcitonin', 'Bacterial infection marker', 'Immune'),
('RF', 0, 14, 'IU/mL', 'Rheumatoid Factor', 'Autoimmune marker', 'Immune'),
('ANA', 0, 0, 'titer', 'Antinuclear Antibody', 'Autoimmune screening', 'Immune'),

-- Thyroid & Hormones
('TSH', 0.4, 4.0, 'µIU/mL', 'Thyroid Stimulating Hormone', 'Thyroid function regulator', 'Endocrine'),
('FT4', 0.8, 1.8, 'ng/dL', 'Free Thyroxine', 'Active thyroid hormone', 'Endocrine'),
('FT3', 2.3, 4.2, 'pg/mL', 'Free Triiodothyronine', 'Active thyroid hormone', 'Endocrine'),
('TOTAL_T4', 4.5, 12.0, 'µg/dL', 'Total Thyroxine', 'Total circulating T4', 'Endocrine'),
('TOTAL_T3', 80, 200, 'ng/dL', 'Total Triiodothyronine', 'Total circulating T3', 'Endocrine'),
('ANTI_TPO', 0, 35, 'IU/mL', 'Anti-Thyroid Peroxidase Antibody', 'Autoimmune thyroid disease marker', 'Immune'),
('ANTI_TG', 0, 40, 'IU/mL', 'Anti-Thyroglobulin Antibody', 'Autoimmune thyroid disease marker', 'Immune'),

-- Reproductive Hormones
('TESTOST_TOTAL', 300, 1000, 'ng/dL', 'Total Testosterone', 'Male hormone', 'Reproductive'),
('TESTOST_FREE', 5, 21, 'ng/dL', 'Free Testosterone', 'Biologically active testosterone', 'Reproductive'),
('ESTRADIOL', 15, 350, 'pg/mL', 'Estradiol', 'Female hormone', 'Reproductive'),
('PROGEST', 0.1, 20, 'ng/mL', 'Progesterone', 'Menstrual & pregnancy hormone', 'Reproductive'),
('FSH', 1.5, 12.4, 'mIU/mL', 'Follicle Stimulating Hormone', 'Reproductive hormone', 'Reproductive'),
('LH', 1.7, 8.6, 'mIU/mL', 'Luteinizing Hormone', 'Reproductive hormone', 'Reproductive'),
('PROLACTIN', 4.0, 23.0, 'ng/mL', 'Prolactin', 'Milk production hormone', 'Endocrine'),
('AMH', 1.0, 4.0, 'ng/mL', 'Anti-Müllerian Hormone', 'Ovarian reserve marker', 'Reproductive'),

-- Adrenal Function
('CORTISOL_AM', 5, 25, 'µg/dL', 'Cortisol (AM)', 'Stress & adrenal function', 'Endocrine'),
('CORTISOL_PM', 2, 9, 'µg/dL', 'Cortisol (PM)', 'Stress & adrenal function', 'Endocrine'),
('ACTH', 7.2, 63.3, 'pg/mL', 'Adrenocorticotropic Hormone', 'Stimulates cortisol release', 'Endocrine'),
('ALDOST', 4, 31, 'ng/dL', 'Aldosterone', 'Blood pressure & salt balance', 'Endocrine'),
('RENIN', 0.25, 5.82, 'ng/mL/hr', 'Plasma Renin Activity', 'Blood pressure regulation', 'Endocrine'),

-- Nutritional & Vitamins
('VITD25OH', 30, 100, 'ng/mL', '25-Hydroxy Vitamin D', 'Vitamin D status', 'Nutritional'),
('VITB12', 200, 900, 'pg/mL', 'Vitamin B12', 'Neurological function', 'Nutritional'),
('FOLATE', 2.7, 17.0, 'ng/mL', 'Folate', 'DNA synthesis', 'Nutritional'),
('VIT_A', 20, 60, 'µg/dL', 'Vitamin A', 'Vision & immune function', 'Nutritional'),
('VIT_E', 5.5, 17.0, 'mg/L', 'Vitamin E', 'Antioxidant', 'Nutritional'),
('VIT_K', 0.2, 3.2, 'ng/mL', 'Vitamin K', 'Blood clotting', 'Nutritional'),
('ZINC', 60, 130, 'µg/dL', 'Zinc', 'Wound healing & immunity', 'Nutritional'),
('COPPER', 70, 140, 'µg/dL', 'Copper', 'Enzyme cofactor', 'Nutritional'),
('SELENIUM', 70, 150, 'µg/L', 'Selenium', 'Antioxidant enzyme cofactor', 'Nutritional'),
('IRON', 50, 170, 'µg/dL', 'Serum Iron', 'Oxygen transport', 'Hematology'),
('TIBC', 240, 450, 'µg/dL', 'Total Iron Binding Capacity', 'Iron metabolism', 'Hematology'),
('FERRITIN', 30, 400, 'ng/mL', 'Ferritin', 'Iron storage', 'Hematology'),
('TRANSFERRIN', 200, 360, 'mg/dL', 'Transferrin', 'Iron transport', 'Hematology'),

-- Infectious Disease
('HBSAG', 0, 0, 'index', 'Hepatitis B Surface Antigen', 'Marker of Hepatitis B infection', 'Infectious Disease'),
('ANTI_HBS', 10, 1000, 'mIU/mL', 'Hepatitis B Surface Antibody', 'Immunity to Hepatitis B', 'Infectious Disease'),
('ANTI_HCV', 0, 0, 'index', 'Hepatitis C Antibody', 'Marker of Hepatitis C infection', 'Infectious Disease'),
('HIV1_2_AB', 0, 0, 'index', 'HIV 1/2 Antibodies', 'HIV infection marker', 'Infectious Disease'),
('HIV_P24', 0, 0, 'pg/mL', 'HIV p24 Antigen', 'Early HIV detection', 'Infectious Disease'),
('VDRL', 0, 0, 'titer', 'Venereal Disease Research Lab Test', 'Syphilis screening', 'Infectious Disease'),
('TPHA', 0, 0, 'titer', 'Treponema pallidum Hemagglutination Assay', 'Syphilis confirmation', 'Infectious Disease'),
('DENGUE_NS1', 0, 0, 'index', 'Dengue NS1 Antigen', 'Early dengue detection', 'Infectious Disease'),
('DENGUE_IGM', 0, 0, 'index', 'Dengue IgM Antibody', 'Acute dengue', 'Infectious Disease'),
('DENGUE_IGG', 0, 0, 'index', 'Dengue IgG Antibody', 'Past dengue infection', 'Infectious Disease'),
('MALARIA_PF', 0, 0, 'index', 'Malaria Plasmodium falciparum', 'Rapid malaria test', 'Infectious Disease'),
('MALARIA_PV', 0, 0, 'index', 'Malaria Plasmodium vivax', 'Rapid malaria test', 'Infectious Disease'),

-- Tumor Markers
('PSA_TOTAL', 0, 4, 'ng/mL', 'Prostate Specific Antigen (Total)', 'Prostate cancer screening', 'Oncology'),
('PSA_FREE', 0, 0.9, 'ng/mL', 'Prostate Specific Antigen (Free)', 'Prostate health', 'Oncology'),
('CEA', 0, 3, 'ng/mL', 'Carcinoembryonic Antigen', 'GI cancer marker', 'Oncology'),
('CA125', 0, 35, 'U/mL', 'Cancer Antigen 125', 'Ovarian cancer marker', 'Oncology'),
('CA19_9', 0, 37, 'U/mL', 'Cancer Antigen 19-9', 'Pancreatic cancer marker', 'Oncology'),
('AFP', 0, 10, 'ng/mL', 'Alpha-Fetoprotein', 'Liver cancer marker', 'Oncology'),
('BETA_HCG', 0, 5, 'mIU/mL', 'Beta-Human Chorionic Gonadotropin', 'Pregnancy & tumor marker', 'Reproductive/Oncology'),

-- Urine Chemistry
('URINE_PH', 4.5, 8.0, '', 'Urine pH', 'Acidity/alkalinity of urine', 'Renal'),
('URINE_SPEC_GRAV', 1.005, 1.030, '', 'Specific Gravity', 'Urine concentration', 'Renal'),
('URINE_PROTEIN', 0, 0.15, 'g/L', 'Urine Protein', 'Proteinuria marker', 'Renal'),
('URINE_GLUCOSE', 0, 0, 'mg/dL', 'Urine Glucose', 'Glycosuria marker', 'Renal/Metabolic'),
('URINE_KETONE', 0, 0, 'mg/dL', 'Urine Ketones', 'Ketosis marker', 'Metabolic'),
('URINE_BILIRUBIN', 0, 0, 'mg/dL', 'Urine Bilirubin', 'Bile pigment presence', 'Hepatic'),
('URINE_UROBILINOGEN', 0.1, 1.0, 'mg/dL', 'Urine Urobilinogen', 'Liver function marker', 'Hepatic'),
('URINE_BLOOD', 0, 0, '', 'Urine Occult Blood', 'Hematuria marker', 'Renal/Urology'),
('URINE_NITRITE', 0, 0, '', 'Urine Nitrite', 'Bacterial infection marker', 'Renal/Infectious'),
('URINE_LEUKOCYTE', 0, 0, '', 'Urine Leukocyte Esterase', 'UTI indicator', 'Renal/Infectious'),
('URINE_CALCIUM', 0, 250, 'mg/day', 'Urine Calcium', 'Kidney stone risk', 'Renal'),
('URINE_SODIUM', 40, 220, 'mEq/day', 'Urine Sodium', 'Salt balance', 'Renal'),
('URINE_POTASSIUM', 25, 125, 'mEq/day', 'Urine Potassium', 'Electrolyte excretion', 'Renal'),
('URINE_CREATININE', 500, 2000, 'mg/day', 'Urine Creatinine', 'Kidney filtration', 'Renal'),

-- Stool Studies
('STOOL_OCCULT_BLOOD', 0, 0, '', 'Stool Occult Blood', 'GI bleeding marker', 'GI'),
('STOOL_PH', 6.0, 7.5, '', 'Stool pH', 'GI function', 'GI'),
('STOOL_FAT', 0, 7, 'g/day', 'Fecal Fat', 'Malabsorption marker', 'GI'),
('STOOL_WBC', 0, 0, '', 'Stool White Blood Cells', 'GI infection', 'GI/Infectious'),
('STOOL_PARASITE', 0, 0, '', 'Stool Parasite Exam', 'Parasite detection', 'Infectious'),
('STOOL_CALPROTECTIN', 0, 50, 'µg/g', 'Stool Calprotectin', 'Inflammatory bowel disease marker', 'GI/Immune'),
('STOOL_LACTOFERRIN', 0, 7.24, 'µg/g', 'Stool Lactoferrin', 'Intestinal inflammation marker', 'GI/Immune'),

-- Cerebrospinal Fluid (CSF)
('CSF_PRESSURE', 70, 180, 'mmH2O', 'Opening Pressure', 'CSF dynamics', 'Neuro'),
('CSF_PROTEIN', 15, 45, 'mg/dL', 'CSF Protein', 'Neuroinflammation marker', 'Neuro'),
('CSF_GLUCOSE', 40, 70, 'mg/dL', 'CSF Glucose', 'Neuroinfection marker', 'Neuro'),
('CSF_CELL_COUNT', 0, 5, 'cells/µL', 'CSF Cell Count', 'Infection or inflammation', 'Neuro'),

-- Pleural, Ascitic, Synovial Fluid
('PLEURAL_PROTEIN', 1.0, 3.0, 'g/dL', 'Pleural Fluid Protein', 'Exudate vs transudate', 'Respiratory'),
('PLEURAL_LDH', 50, 200, 'U/L', 'Pleural Fluid LDH', 'Exudate vs transudate', 'Respiratory'),
('ASCITIC_PROTEIN', 1.0, 3.0, 'g/dL', 'Ascitic Fluid Protein', 'Ascites classification', 'GI'),
('SYNOVIAL_WBC', 0, 200, 'cells/µL', 'Synovial Fluid WBC Count', 'Joint inflammation marker', 'Musculoskeletal'),
('SYNOVIAL_PROTEIN', 1.0, 3.0, 'g/dL', 'Synovial Fluid Protein', 'Joint disease marker', 'Musculoskeletal'),

-- Cardiac Markers
('TROPONIN_T', 0, 0.01, 'ng/mL', 'Troponin T', 'Myocardial injury marker', 'Cardiac'),
('TROPONIN_I', 0, 0.04, 'ng/mL', 'Troponin I', 'Myocardial injury marker', 'Cardiac'),
('BNP', 0, 100, 'pg/mL', 'B-Type Natriuretic Peptide', 'Heart failure marker', 'Cardiac'),
('NT_PROBNP', 0, 125, 'pg/mL', 'N-terminal pro-BNP', 'Heart failure marker', 'Cardiac'),
('CK_MB', 0, 5, 'ng/mL', 'Creatine Kinase-MB', 'Heart muscle injury marker', 'Cardiac'),

-- Toxicology & Substance Levels
('ALCOHOL_SERUM', 0, 0.02, 'g/dL', 'Blood Alcohol', 'Ethanol intoxication marker', 'Toxicology'),
('PARACETAMOL', 0, 20, 'µg/mL', 'Acetaminophen Level', 'Toxicity monitoring', 'Toxicology'),
('SALICYLATE', 0, 20, 'mg/dL', 'Salicylate Level', 'Toxicity monitoring', 'Toxicology'),
('CO_LEVEL', 0, 3, '%HbCO', 'Carboxyhemoglobin', 'Carbon monoxide exposure', 'Toxicology'),
('LEAD_BLOOD', 0, 5, 'µg/dL', 'Blood Lead Level', 'Lead poisoning marker', 'Toxicology'),
('MERCURY_BLOOD', 0, 5, 'µg/L', 'Blood Mercury', 'Mercury exposure marker', 'Toxicology'),
('ARSENIC_BLOOD', 0, 10, 'µg/L', 'Blood Arsenic', 'Arsenic exposure marker', 'Toxicology'),

-- Allergy & Immune Markers
('TOTAL_IGE', 0, 100, 'IU/mL', 'Total IgE', 'Allergy marker', 'Immune'),
('CRP_HS', 0, 3, 'mg/L', 'High Sensitivity C-Reactive Protein', 'Cardiac inflammation marker', 'Immune'),
('ESR', 0, 20, 'mm/hr', 'Erythrocyte Sedimentation Rate', 'Inflammation marker', 'Immune'),
('IL6', 0, 7, 'pg/mL', 'Interleukin-6', 'Inflammatory cytokine', 'Immune'),
('TNF_ALPHA', 0, 8, 'pg/mL', 'Tumor Necrosis Factor-alpha', 'Inflammatory cytokine', 'Immune'),
('ANA', 0, 0, 'index', 'Antinuclear Antibody', 'Autoimmune marker', 'Immune'),
('RF', 0, 14, 'IU/mL', 'Rheumatoid Factor', 'Arthritis marker', 'Immune'),
('ANTI_CCP', 0, 20, 'U/mL', 'Anti-Cyclic Citrullinated Peptide Antibody', 'Rheumatoid arthritis marker', 'Immune'),

-- Osmolality and Electrolyte Balance
('SERUM_OSMOLALITY', 275, 295, 'mOsm/kg', 'Serum Osmolality', 'Concentration of solutes in blood', 'Metabolic'),

-- White Blood Cell Differentials
('WBC_TOTAL', 4.0, 11.0, 'x10^9/L', 'Total White Blood Cell Count', 'Immune function marker', 'Hematology'),
('NEUTROPHIL_PERCENT', 40, 70, '%', 'Neutrophils %', 'Bacterial infection marker', 'Hematology'),
('LYMPHOCYTE_PERCENT', 20, 45, '%', 'Lymphocytes %', 'Viral infection/immune status', 'Hematology'),
('MONOCYTE_PERCENT', 2, 8, '%', 'Monocytes %', 'Chronic infection marker', 'Hematology'),
('EOSINOPHIL_PERCENT', 1, 6, '%', 'Eosinophils %', 'Allergy/parasite marker', 'Hematology'),
('BASOPHIL_PERCENT', 0, 1, '%', 'Basophils %', 'Allergy/inflammation marker', 'Hematology'),

-- Absolute Differential Counts
('NEUTROPHIL_ABS', 1.8, 7.5, 'x10^9/L', 'Absolute Neutrophil Count', 'Bacterial infection marker', 'Hematology'),
('LYMPHOCYTE_ABS', 1.0, 3.5, 'x10^9/L', 'Absolute Lymphocyte Count', 'Viral infection/immune status', 'Hematology'),
('MONOCYTE_ABS', 0.2, 0.8, 'x10^9/L', 'Absolute Monocyte Count', 'Chronic infection marker', 'Hematology'),
('EOSINOPHIL_ABS', 0.04, 0.4, 'x10^9/L', 'Absolute Eosinophil Count', 'Allergy/parasite marker', 'Hematology'),
('BASOPHIL_ABS', 0, 0.1, 'x10^9/L', 'Absolute Basophil Count', 'Allergy/inflammation marker', 'Hematology'),

-- Red Blood Cell Indices
('RBC_COUNT', 4.2, 5.9, 'x10^12/L', 'Red Blood Cell Count', 'Oxygen-carrying capacity', 'Hematology'),
('HEMOGLOBIN', 13.5, 17.5, 'g/dL', 'Hemoglobin', 'Oxygen transport protein', 'Hematology'),
('HEMATOCRIT', 38, 50, '%', 'Hematocrit', 'Proportion of red cells in blood', 'Hematology'),
('MCV', 80, 100, 'fL', 'Mean Corpuscular Volume', 'RBC size', 'Hematology'),
('MCH', 27, 34, 'pg', 'Mean Corpuscular Hemoglobin', 'Hb per RBC', 'Hematology'),
('MCHC', 32, 36, 'g/dL', 'Mean Corpuscular Hemoglobin Concentration', 'Hb concentration in RBCs', 'Hematology'),
('RDW', 11.5, 14.5, '%', 'Red Cell Distribution Width', 'Variation in RBC size', 'Hematology'),

-- Platelets and Coagulation
('PLATELET_COUNT', 150, 450, 'x10^9/L', 'Platelet Count', 'Clotting function marker', 'Hematology'),
('MPV', 7.5, 11.5, 'fL', 'Mean Platelet Volume', 'Platelet size', 'Hematology'),
('PT', 11, 13.5, 'sec', 'Prothrombin Time', 'Clotting factor activity', 'Hematology'),
('INR', 0.8, 1.2, '', 'International Normalized Ratio', 'Clotting standardization', 'Hematology'),
('APTT', 25, 35, 'sec', 'Activated Partial Thromboplastin Time', 'Intrinsic clotting pathway', 'Hematology'),
('FIBRINOGEN', 200, 400, 'mg/dL', 'Fibrinogen', 'Clot formation protein', 'Hematology'),

-- Coagulation Factors
('FACTOR_VIII', 50, 150, '%', 'Factor VIII', 'Hemophilia A marker', 'Hematology'),
('FACTOR_IX', 50, 150, '%', 'Factor IX', 'Hemophilia B marker', 'Hematology'),
('FACTOR_XIII', 70, 130, '%', 'Factor XIII', 'Clot stability factor', 'Hematology'),
('D_DIMER', 0, 0.5, 'µg/mL FEU', 'D-Dimer', 'Fibrin degradation product', 'Hematology'),

-- Genetic & Molecular Markers
('BRCA1', 0, 0, 'index', 'BRCA1', 'Breast cancer susceptibility gene', 'Genetic'),
('BRCA2', 0, 0, 'index', 'BRCA2', 'Breast cancer susceptibility gene', 'Genetic'),
('KRAS', 0, 0, 'index', 'KRAS', 'Colorectal cancer marker', 'Genetic'),
('EGFR', 0, 0, 'index', 'EGFR', 'Lung cancer marker', 'Genetic'),
('TP53', 0, 0, 'index', 'TP53', 'Tumor suppressor gene', 'Genetic'),
('MLH1', 0, 0, 'index', 'MLH1', 'Lynch syndrome marker', 'Genetic'),
('MSH2', 0, 0, 'index', 'MSH2', 'Lynch syndrome marker', 'Genetic'),
('MSH6', 0, 0, 'index', 'MSH6', 'Lynch syndrome marker', 'Genetic'),
('PMS2', 0, 0, 'index', 'PMS2', 'Lynch syndrome marker', 'Genetic'),
('HER2/neu', 0, 3, 'index', 'HER2/neu', 'Breast cancer marker', 'Oncology'),

-- Genetic Testing
('CFTR', 0, 0, 'index', 'Cystic Fibrosis Transmembrane Conductance Regulator', 'Cystic fibrosis marker', 'Genetic'),
('SMA', 0, 0, 'index', 'Spinal Muscular Atrophy', 'SMA carrier screening', 'Genetic'),
('FMR1', 0, 0, 'index', 'Fragile X Mental Retardation 1', 'Fragile X syndrome marker', 'Genetic'),
('G6PD', 0, 0, 'index', 'Glucose-6-Phosphate Dehydrogenase Deficiency', 'G6PD deficiency marker', 'Genetic');

