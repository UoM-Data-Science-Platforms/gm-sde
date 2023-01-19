const rp = require('request-promise');
const cheerio = require('cheerio');
const { join } = require('path');
const fs = require('fs');
const archiver = require('archiver');

const CACHED_DIR = join(__dirname, 'cached-data-files');
const OUTPUT_DIR = join(__dirname, 'output');
const CHUNK_DIR = join(OUTPUT_DIR, 'chunks');
const OUTPUT_FILE_NAME = 'gp-population-data-by-sex-and-age.csv';
const OUTPUT_FILE = join(OUTPUT_DIR, OUTPUT_FILE_NAME);
const OUTPUT_FILE_ZIPPED = join(OUTPUT_DIR, 'gp-population-data-by-sex-and-age.zip');
//
const months = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

// The codes for the 10 localities in Greater Manchester. Prior to 2023 these were called CCGs.
// NB prior to 2017, there was also Central Manchester (00W), North Manchester (01M) and South
// Manchester (01N). These 3 merged into just Manchester (14L) in early 2017.
const ccgs = [
  '01G',
  '00T',
  '01D',
  '02A',
  '01W',
  '00Y',
  '02H',
  '00V',
  '14L',
  '01Y',
  '00W',
  '01M',
  '01N',
];

const baseUrl =
  'https://digital.nhs.uk/data-and-information/publications/statistical/patients-registered-at-a-gp-practice/';

function getDateParts(date) {
  const month = ('0' + (date.getMonth() + 1)).slice(-2); //numeric month (1-12) left padded with zeros (01, 02,...,12)
  const monthName = months[date.getMonth()];
  const monthCamelCase = monthName[0].toUpperCase() + monthName.slice(1);
  const year4chars = date.getFullYear();
  const year2chars = date.getYear();
  return { month, year4chars, year2chars, monthName, monthCamelCase };
}

function dateStringForUrl(date) {
  const { monthName, year4chars } = getDateParts(date);
  return `${monthName}-${year4chars}`;
}

function readableDate(date) {
  const { monthCamelCase, year4chars } = getDateParts(date);
  return `${monthCamelCase} ${year4chars}`;
}

function urlFromDate(date) {
  const dateString = dateStringForUrl(date);
  if (dateString === 'october-2017')
    return `${baseUrl}patients-registered-at-a-gp-practice-october-2017-special-topic-practice-list-size-comparison-october-2013-to-october-2017`;
  return `${baseUrl}${dateString}`;
}

function populateDateArray(startDate, endDate) {
  const dates = [];
  while (startDate < endDate) {
    dates.push(new Date(startDate));
    startDate.setMonth(startDate.getMonth() + 1);
  }
  return dates;
}

async function getDataFileUrls(datesToGetDataFor) {
  return Promise.all(
    datesToGetDataFor.map((date) =>
      rp({
        uri: urlFromDate(date),
        headers: {
          Origin: 'Request-promise',
        },
      })
        .then((html) => {
          var $ = cheerio.load(html);
          var maleUrl = $('a[onclick*="gp-reg-pat-prac-sing-age-male"]').attr('href');
          var femaleUrl = $('a[onclick*="gp-reg-pat-prac-sing-age-female"]').attr('href');
          var singleUrl =
            $('a[onclick*="gp-reg-patients-prac-sing-year-age"]').attr('href') ||
            $('a[onclick*="gp_syoa"]').attr('href');
          const { month, year4chars } = getDateParts(date);
          var single5YrUrl = $(`a[onclick*="gp-reg-patients-${month}-${year4chars}.csv"]`).attr(
            'href'
          );
          return { date, maleUrl, femaleUrl, singleUrl, single5YrUrl };
        })
        .catch(() => {
          // guess it doesn't exist
          console.log(
            `No data found for ${readableDate(
              date
            )}. This is not necessarily an error as the data wasn't released on a monthly basis in the past.`
          );
        })
    )
  );
}

const fileFormat = {
  format1: {
    name: 'format1',
    header:
      'practice_code,postcode,ccg_code,ons_ccg_code,nhse_region_code,ons_region_code,nhse_comm_region_code,ons_comm_region_code,total_all,total_male,total_female,male_0_1,male_1_2,male_2_3,male_3_4,male_4_5,male_5_6,male_6_7,male_7_8,male_8_9,male_9_10,male_10_11,male_11_12,male_12_13,male_13_14,male_14_15,male_15_16,male_16_17,male_17_18,male_18_19,male_19_20,male_20_21,male_21_22,male_22_23,male_23_24,male_24_25,male_25_26,male_26_27,male_27_28,male_28_29,male_29_30,male_30_31,male_31_32,male_32_33,male_33_34,male_34_35,male_35_36,male_36_37,male_37_38,male_38_39,male_39_40,male_40_41,male_41_42,male_42_43,male_43_44,male_44_45,male_45_46,male_46_47,male_47_48,male_48_49,male_49_50,male_50_51,male_51_52,male_52_53,male_53_54,male_54_55,male_55_56,male_56_57,male_57_58,male_58_59,male_59_60,male_60_61,male_61_62,male_62_63,male_63_64,male_64_65,male_65_66,male_66_67,male_67_68,male_68_69,male_69_70,male_70_71,male_71_72,male_72_73,male_73_74,male_74_75,male_75_76,male_76_77,male_77_78,male_78_79,male_79_80,male_80_81,male_81_82,male_82_83,male_83_84,male_84_85,male_85_86,male_86_87,male_87_88,male_88_89,male_89_90,male_90_91,male_91_92,male_92_93,male_93_94,male_94_95,male_95+,female_0_1,female_1_2,female_2_3,female_3_4,female_4_5,female_5_6,female_6_7,female_7_8,female_8_9,female_9_10,female_10_11,female_11_12,female_12_13,female_13_14,female_14_15,female_15_16,female_16_17,female_17_18,female_18_19,female_19_20,female_20_21,female_21_22,female_22_23,female_23_24,female_24_25,female_25_26,female_26_27,female_27_28,female_28_29,female_29_30,female_30_31,female_31_32,female_32_33,female_33_34,female_34_35,female_35_36,female_36_37,female_37_38,female_38_39,female_39_40,female_40_41,female_41_42,female_42_43,female_43_44,female_44_45,female_45_46,female_46_47,female_47_48,female_48_49,female_49_50,female_50_51,female_51_52,female_52_53,female_53_54,female_54_55,female_55_56,female_56_57,female_57_58,female_58_59,female_59_60,female_60_61,female_61_62,female_62_63,female_63_64,female_64_65,female_65_66,female_66_67,female_67_68,female_68_69,female_69_70,female_70_71,female_71_72,female_72_73,female_73_74,female_74_75,female_75_76,female_76_77,female_77_78,female_78_79,female_79_80,female_80_81,female_81_82,female_82_83,female_83_84,female_84_85,female_85_86,female_86_87,female_87_88,female_88_89,female_89_90,female_90_91,female_91_92,female_92_93,female_93_94,female_94_95,female_95+',
  },
  format2: {
    name: 'format2',
    header:
      'practice_code,postcode,ccg_code,ons_ccg_code,nhse_region_code,ons_region_code,nhse_comm_region_code,ons_comm_rgn_code,total_all,total_male,total_female,male_0_1,male_1_2,male_2_3,male_3_4,male_4,male_5,male_6,male_7_8,male_8_9,male_9_10,male_10_11,male_11_12,male_12_13,male_13_14,male_14_15,male_15_16,male_16_17,male_17_18,male_18_19,male_19_20,male_20_21,male_21_22,male_22_23,male_23_24,male_24_25,male_25_26,male_26_27,male_27_28,male_28_29,male_29_30,male_30_31,male_31_32,male_32_33,male_33_34,male_34_35,male_35_36,male_36_37,male_37_38,male_38_39,male_39_40,male_40_41,male_41_42,male_42_43,male_43_44,male_44_45,male_45_46,male_46_47,male_47_48,male_48_49,male_49_50,male_50_51,male_51_52,male_52_53,male_53_54,male_54_55,male_55_56,male_56_57,male_57_58,male_58_59,male_59_60,male_60_61,male_61_62,male_62_63,male_63_64,male_64_65,male_65_66,male_66_67,male_67_68,male_68_69,male_69_70,male_70_71,male_71_72,male_72_73,male_73_74,male_74_75,male_75_76,male_76_77,male_77_78,male_78_79,male_79_80,male_80_81,male_81_82,male_82_83,male_83_84,male_84_85,male_85_86,male_86_87,male_87_88,male_88_89,male_89_90,male_90_91,male_91_92,male_92_93,male_93_94,male_94_95,male_95+,female_0_1,female_1_2,female_2_3,female_3_4,female_4_5,female_5_6,female_6_7,female_7_8,female_8_9,female_9_10,female_10_11,female_11_12,female_12_13,female_13_14,female_14_15,female_15_16,female_16_17,female_17_18,female_18_19,female_19_20,female_20_21,female_21_22,female_22_23,female_23_24,female_24_25,female_25_26,female_26_27,female_27_28,female_28_29,female_29_30,female_30_31,female_31_32,female_32_33,female_33_34,female_34_35,female_35_36,female_36_37,female_37_38,female_38_39,female_39_40,female_40_41,female_41_42,female_42_43,female_43_44,female_44_45,female_45_46,female_46_47,female_47_48,female_48_49,female_49_50,female_50_51,female_51_52,female_52_53,female_53_54,female_54_55,female_55_56,female_56_57,female_57_58,female_58_59,female_59_60,female_60_61,female_61_62,female_62_63,female_63_64,female_64_65,female_65_66,female_66_67,female_67_68,female_68_69,female_69_70,female_70_71,female_71_72,female_72_73,female_73_74,female_74_75,female_75_76,female_76_77,female_77_78,female_78_79,female_79_80,female_80_81,female_81_82,female_82_83,female_83_84,female_84_85,female_85_86,female_86_87,female_87_88,female_88_89,female_89_90,female_90_91,female_91_92,female_92_93,female_93_94,female_94_95,female_95+',
  },
  format3: {
    name: 'format3',
    header:
      'practice_code,postcode,ons_ccg_code,ccg_code,ons_region_code,nhse_region_code,ons_comm_rgn_code,nhse_comm_region_code,total_all,total_male,total_female,male_0_1,male_1_2,male_2_3,male_3_4,male_4_5,male_5_6,male_6_7,male_7_8,male_8_9,male_9_10,male_10_11,male_11_12,male_12_13,male_13_14,male_14_15,male_15_16,male_16_17,male_17_18,male_18_19,male_19_20,male_20_21,male_21_22,male_22_23,male_23_24,male_24_25,male_25_26,male_26_27,male_27_28,male_28_29,male_29_30,male_30_31,male_31_32,male_32_33,male_33_34,male_34_35,male_35_36,male_36_37,male_37_38,male_38_39,male_39_40,male_40_41,male_41_42,male_42_43,male_43_44,male_44_45,male_45_46,male_46_47,male_47_48,male_48_49,male_49_50,male_50_51,male_51_52,male_52_53,male_53_54,male_54_55,male_55_56,male_56_57,male_57_58,male_58_59,male_59_60,male_60_61,male_61_62,male_62_63,male_63_64,male_64_65,male_65_66,male_66_67,male_67_68,male_68_69,male_69_70,male_70_71,male_71_72,male_72_73,male_73_74,male_74_75,male_75_76,male_76_77,male_77_78,male_78_79,male_79_80,male_80_81,male_81_82,male_82_83,male_83_84,male_84_85,male_85_86,male_86_87,male_87_88,male_88_89,male_89_90,male_90_91,male_91_92,male_92_93,male_93_94,male_94_95,male_95+,female_0_1,female_1_2,female_2_3,female_3_4,female_4_5,female_5_6,female_6_7,female_7_8,female_8_9,female_9_10,female_10_11,female_11_12,female_12_13,female_13_14,female_14_15,female_15_16,female_16_17,female_17_18,female_18_19,female_19_20,female_20_21,female_21_22,female_22_23,female_23_24,female_24_25,female_25_26,female_26_27,female_27_28,female_28_29,female_29_30,female_30_31,female_31_32,female_32_33,female_33_34,female_34_35,female_35_36,female_36_37,female_37_38,female_38_39,female_39_40,female_40_41,female_41_42,female_42_43,female_43_44,female_44_45,female_45_46,female_46_47,female_47_48,female_48_49,female_49_50,female_50_51,female_51_52,female_52_53,female_53_54,female_54_55,female_55_56,female_56_57,female_57_58,female_58_59,female_59_60,female_60_61,female_61_62,female_62_63,female_63_64,female_64_65,female_65_66,female_66_67,female_67_68,female_68_69,female_69_70,female_70_71,female_71_72,female_72_73,female_73_74,female_74_75,female_75_76,female_76_77,female_77_78,female_78_79,female_79_80,female_80_81,female_81_82,female_82_83,female_83_84,female_84_85,female_85_86,female_86_87,female_87_88,female_88_89,female_89_90,female_90_91,female_91_92,female_92_93,female_93_94,female_94_95,female_95+',
  },
  format4: {
    name: 'format4',
    header:
      'practice_code,postcode,parent_organisation_code,nhse_area_team,nhse_region,total_all,total_male,total_female,male_0_1,male_1_2,male_2_3,male_3_4,male_4,male_5,male_6,male_7_8,male_8_9,male_9_10,male_10_11,male_11_12,male_12_13,male_13_14,male_14_15,male_15_16,male_16_17,male_17_18,male_18_19,male_19_20,male_20_21,male_21_22,male_22_23,male_23_24,male_24_25,male_25_26,male_26_27,male_27_28,male_28_29,male_29_30,male_30_31,male_31_32,male_32_33,male_33_34,male_34_35,male_35_36,male_36_37,male_37_38,male_38_39,male_39_40,male_40_41,male_41_42,male_42_43,male_43_44,male_44_45,male_45_46,male_46_47,male_47_48,male_48_49,male_49_50,male_50_51,male_51_52,male_52_53,male_53_54,male_54_55,male_55_56,male_56_57,male_57_58,male_58_59,male_59_60,male_60_61,male_61_62,male_62_63,male_63_64,male_64_65,male_65_66,male_66_67,male_67_68,male_68_69,male_69_70,male_70_71,male_71_72,male_72_73,male_73_74,male_74_75,male_75_76,male_76_77,male_77_78,male_78_79,male_79_80,male_80_81,male_81_82,male_82_83,male_83_84,male_84_85,male_85_86,male_86_87,male_87_88,male_88_89,male_89_90,male_90_91,male_91_92,male_92_93,male_93_94,male_94_95,male_95+,female_0_1,female_1_2,female_2_3,female_3_4,female_4_5,female_5_6,female_6_7,female_7_8,female_8_9,female_9_10,female_10_11,female_11_12,female_12_13,female_13_14,female_14_15,female_15_16,female_16_17,female_17_18,female_18_19,female_19_20,female_20_21,female_21_22,female_22_23,female_23_24,female_24_25,female_25_26,female_26_27,female_27_28,female_28_29,female_29_30,female_30_31,female_31_32,female_32_33,female_33_34,female_34_35,female_35_36,female_36_37,female_37_38,female_38_39,female_39_40,female_40_41,female_41_42,female_42_43,female_43_44,female_44_45,female_45_46,female_46_47,female_47_48,female_48_49,female_49_50,female_50_51,female_51_52,female_52_53,female_53_54,female_54_55,female_55_56,female_56_57,female_57_58,female_58_59,female_59_60,female_60_61,female_61_62,female_62_63,female_63_64,female_64_65,female_65_66,female_66_67,female_67_68,female_68_69,female_69_70,female_70_71,female_71_72,female_72_73,female_73_74,female_74_75,female_75_76,female_76_77,female_77_78,female_78_79,female_79_80,female_80_81,female_81_82,female_82_83,female_83_84,female_84_85,female_85_86,female_86_87,female_87_88,female_88_89,female_89_90,female_90_91,female_91_92,female_92_93,female_93_94,female_94_95,female_95+',
  },
  format5: {
    name: 'format5',
    header:
      'practice_code,postcode,ons_ccg_code,ccg_code,ons_region_code,nhse_region_code,ons_comm_rgn_code,nhse_comm_region_code,total_all,total_male,total_female,male_0_1,male_1_2,male_2_3,male_3_4,male_4,male_5,male_6,male_7_8,male_8_9,male_9_10,male_10_11,male_11_12,male_12_13,male_13_14,male_14_15,male_15_16,male_16_17,male_17_18,male_18_19,male_19_20,male_20_21,male_21_22,male_22_23,male_23_24,male_24_25,male_25_26,male_26_27,male_27_28,male_28_29,male_29_30,male_30_31,male_31_32,male_32_33,male_33_34,male_34_35,male_35_36,male_36_37,male_37_38,male_38_39,male_39_40,male_40_41,male_41_42,male_42_43,male_43_44,male_44_45,male_45_46,male_46_47,male_47_48,male_48_49,male_49_50,male_50_51,male_51_52,male_52_53,male_53_54,male_54_55,male_55_56,male_56_57,male_57_58,male_58_59,male_59_60,male_60_61,male_61_62,male_62_63,male_63_64,male_64_65,male_65_66,male_66_67,male_67_68,male_68_69,male_69_70,male_70_71,male_71_72,male_72_73,male_73_74,male_74_75,male_75_76,male_76_77,male_77_78,male_78_79,male_79_80,male_80_81,male_81_82,male_82_83,male_83_84,male_84_85,male_85_86,male_86_87,male_87_88,male_88_89,male_89_90,male_90_91,male_91_92,male_92_93,male_93_94,male_94_95,male_95+,female_0_1,female_1_2,female_2_3,female_3_4,female_4_5,female_5_6,female_6_7,female_7_8,female_8_9,female_9_10,female_10_11,female_11_12,female_12_13,female_13_14,female_14_15,female_15_16,female_16_17,female_17_18,female_18_19,female_19_20,female_20_21,female_21_22,female_22_23,female_23_24,female_24_25,female_25_26,female_26_27,female_27_28,female_28_29,female_29_30,female_30_31,female_31_32,female_32_33,female_33_34,female_34_35,female_35_36,female_36_37,female_37_38,female_38_39,female_39_40,female_40_41,female_41_42,female_42_43,female_43_44,female_44_45,female_45_46,female_46_47,female_47_48,female_48_49,female_49_50,female_50_51,female_51_52,female_52_53,female_53_54,female_54_55,female_55_56,female_56_57,female_57_58,female_58_59,female_59_60,female_60_61,female_61_62,female_62_63,female_63_64,female_64_65,female_65_66,female_66_67,female_67_68,female_68_69,female_69_70,female_70_71,female_71_72,female_72_73,female_73_74,female_74_75,female_75_76,female_76_77,female_77_78,female_78_79,female_79_80,female_80_81,female_81_82,female_82_83,female_83_84,female_84_85,female_85_86,female_86_87,female_87_88,female_88_89,female_89_90,female_90_91,female_91_92,female_92_93,female_93_94,female_94_95,female_95+',
  },
  format6: {
    name: 'format6',
    header:
      'gp_practice_code,postcode,ccg_code,nhse_area_team_code,nhse_region_code,total_all,total_male,total_females,male_0-4,male_5-9,male_10-14,male_15-19,male_20-24,male_25-29,male_30-34,male_35-39,male_40-44,male_45-49,male_50-54,male_55-59,male_60-64,male_65-69,male_70-74,male_75-79,male_80-84,male_85+,female_0-4,female_5-9,female_10-14,female_15-19,female_20-24,female_25-29,female_30-34,female_35-39,female_40-44,female_45-49,female_50-54,female_55-59,female_60-64,female_65-69,female_70-74,female_75-79,female_80-84,female_85+',
  },
  format7: {
    name: 'format7',
    header:
      'gp_practice_code,postcode,ccg_code,nhse_area_team_code,nhse_region_code,total_all,total_male,total_females,male_0-4,male_5-9,male_10-14,male_15-19,male_20-24,male_25-29,male_30-34,male_35-39,male_40-44,male_45-49,male_50-54,male_55-59,male_60-64,male_65-69,male_70-74,male_75-79,male_80-84,male_85-89,male_90-94,male_95+,female_0-4,female_5-9,female_10-14,female_15-19,female_20-24,female_25-29,female_30-34,female_35-39,female_40-44,female_45-49,female_50-54,female_55-59,female_60-64,female_65-69,female_70-74,female_75-79,female_80-84,female_85-89,female_90-94,female_95+',
  },
  format8: {
    name: 'format8',
    header:
      'gp_practice_code,ccg_code,nhse_area_team_code,nhse_region_code,total_all,total_male,total_females,male_0-4,male_5-9,male_10-14,male_15-19,male_20-24,male_25-29,male_30-34,male_35-39,male_40-44,male_45-49,male_50-54,male_55-59,male_60-64,male_65-69,male_70-74,male_75-79,male_80-84,male_85+,female_0-4,female_5-9,female_10-14,female_15-19,female_20-24,female_25-29,female_30-34,female_35-39,female_40-44,female_45-49,female_50-54,female_55-59,female_60-64,female_65-69,female_70-74,female_75-79,female_80-84,female_85+',
  },
};

function processBothSex5YearFile(fileData, fileName) {
  console.log(`Processing male/female data for ${fileName}`);
  const rows = fileData.split('\r\n');
  const header = rows[0];
  let format;
  switch (header.toLowerCase()) {
    case fileFormat.format6.header:
      format = fileFormat.format6.name;
      break;
    case fileFormat.format7.header:
      format = fileFormat.format7.name;
      break;
    case fileFormat.format8.header:
      format = fileFormat.format8.name;
      break;
    default:
      console.log(
        `For the single data 5 year band file for ${fileName} the header row was unexpected:\n\n${header}`
      );
      process.exit(1);
  }

  const dataProcessed = [];
  rows
    .slice(1)
    .filter((x) => x.length > 5)
    .forEach((x) => {
      // Recent files have the following headings
      let [
        practiceId,
        postcode,
        ccg, //nhsAreaCode
        ,
        nhsRegionCode,
        total,
        totalMale,
        totalFemale,
        ...ages
      ] = x.split(',');
      // above is ok for format6 and format7
      if (format === fileFormat.format8.name) {
        ccg = postcode;
        ages = [totalFemale].concat(ages);
        totalFemale = totalMale;
        totalMale = total;
        total = nhsRegionCode;
      }

      if (ccgs.indexOf(ccg) < 0) return;

      const maleAges = ages.slice(0, ages.length / 2);
      const femaleAges = ages.slice(ages.length / 2);

      maleAges
        .map((frequency, age) => ({
          ccg,
          practiceId,
          age: age < maleAges.length - 1 ? `${age * 5}-${age * 5 + 4}` : `${age * 5}+`,
          frequency,
          sex: 'M',
        }))
        .forEach((item) => {
          dataProcessed.push(item);
          total -= item.frequency;
          totalMale -= item.frequency;
        });

      femaleAges
        .map((frequency, age) => ({
          ccg,
          practiceId,
          age: age < femaleAges.length - 1 ? `${age * 5}-${age * 5 + 4}` : `${age * 5}+`,
          frequency,
          sex: 'F',
        }))
        .forEach((item) => {
          dataProcessed.push(item);
          total -= item.frequency;
          totalFemale -= item.frequency;
        });

      if (total !== 0) {
        console.log(
          `The total population for ${practiceId}, in ${fileName}, does not equal the sum of all the individual frequencies.`
        );
        process.exit(1);
      }
      if (totalMale !== 0) {
        console.log(
          `The total male population figure for ${practiceId}, in ${fileName}, does not equal the sum of all the individual frequencies.`
        );
        process.exit(1);
      }
      if (totalFemale !== 0) {
        console.log(
          `The total female population figure for ${practiceId}, in ${fileName}, does not equal the sum of all the individual frequencies.`
        );
        process.exit(1);
      }
    });

  return dataProcessed;
}

function processBothSexFile(fileData, fileName) {
  console.log(`Processing male/female data for ${fileName}`);
  const rows = fileData.split('\r\n');
  const header = rows[0];
  let format;
  switch (header.toLowerCase()) {
    case fileFormat.format1.header:
      format = fileFormat.format1.name;
      break;
    case fileFormat.format2.header:
      format = fileFormat.format2.name;
      break;
    case fileFormat.format3.header:
      format = fileFormat.format3.name;
      break;
    case fileFormat.format4.header:
      format = fileFormat.format4.name;
      break;
    case fileFormat.format5.header:
      format = fileFormat.format5.name;
      break;
    default:
      console.log(
        `For the single data file for ${fileName} the header row was unexpected:\n\n${header}`
      );
      process.exit(1);
  }

  const dataProcessed = [];
  rows
    .slice(1)
    .filter((x) => x.length > 5)
    .forEach((x) => {
      // Recent files have the following headings
      let [
        practiceId, //postcode
        ,
        ccg,
        ccgONS, //nhsRegion
        ,
        nhsRegionONS,
        nhsComm,
        nhsCommONS,
        total,
        totalMale,
        totalFemale,
        ...ages
      ] = x.split(',');
      // above is the same for format1 and format2
      // slight difference for format3, format4, format5
      if (format === fileFormat.format3.name || format === fileFormat.format5.name) {
        ccg = ccgONS;
      } else if (format === fileFormat.format4.name) {
        ages = [total, totalMale, totalFemale].concat(ages);
        total = nhsRegionONS;
        totalMale = nhsComm;
        totalFemale = nhsCommONS;
      }

      if (ccgs.indexOf(ccg) < 0) return;

      const maleAges = ages.slice(0, 96);
      const femaleAges = ages.slice(96);

      maleAges
        .map((frequency, age) => ({
          sex: 'M',
          ccg,
          practiceId,
          age: age < 95 ? age : '95+',
          frequency,
        }))
        .forEach((item) => {
          dataProcessed.push(item);
          total -= item.frequency;
          totalMale -= item.frequency;
        });

      femaleAges
        .map((frequency, age) => ({
          sex: 'F',
          ccg,
          practiceId,
          age: age < 95 ? age : '95+',
          frequency,
        }))
        .forEach((item) => {
          dataProcessed.push(item);
          total -= item.frequency;
          totalFemale -= item.frequency;
        });

      if (total !== 0) {
        console.log(
          `The total population for ${practiceId}, in ${fileName}, does not equal the sum of all the individual frequencies.`
        );
        process.exit(1);
      }
      if (totalMale !== 0) {
        console.log(
          `The total male population figure for ${practiceId}, in ${fileName}, does not equal the sum of all the individual frequencies.`
        );
        process.exit(1);
      }
      if (totalFemale !== 0) {
        console.log(
          `The total female population figure for ${practiceId}, in ${fileName}, does not equal the sum of all the individual frequencies.`
        );
        process.exit(1);
      }
    });

  return dataProcessed;
}

function processSingleSexFile(fileData, year, month, fileName, maleOrFemale) {
  console.log(`Processing ${maleOrFemale} data for ${fileName}`);
  return fileData
    .split('\r\n')
    .slice(1)
    .filter((x) => x.length > 5)
    .map((x) => {
      // Recent files have the following headings
      let [date, ccg, , practiceId, , sex, age, frequency] = x.split(',');

      // Earlier files were a bit different
      if (date === 'GP_PRAC_PAT_LIST') {
        date = ccg;
        // TODO need to work out which CCG for these practices.
        const ccgLookup = getCCGLookup();
        ccg = ccgLookup[practiceId];
        if (!ccg) {
          // Might be an issue - but not if one of the following practices which were
          // new in april 2017
          if (['Y05690', 'Y05622', 'Y05472'].indexOf(practiceId) < 0) {
            console.log(`No practice id in lookup for ${practiceId}`);
            process.exit(1);
          }
        }
      }

      if (sex.toLowerCase() !== maleOrFemale.toLowerCase()) {
        console.log(`Row in ${fileName} where sex is not ${maleOrFemale} -it is: ${sex}`);
      }
      if (
        date.toLowerCase() !== `01${months[+month - 1].substring(0, 3)}${year}` &&
        date.toLowerCase() !== `01-${months[+month - 1].substring(0, 3)}-${year.slice(-2)}`
      ) {
        console.log('Row in ' + fileName + ' where date is ' + date + ' instead of actual.');
      }
      return {
        sex: maleOrFemale[0].toUpperCase(),
        ccg,
        practiceId,
        age,
        frequency,
      };
    })
    .filter((x) => ccgs.indexOf(x.ccg) > -1)
    .filter((x) => x.age.toLowerCase() !== 'all');
}

async function downloadFileIfNotAlready(uri, date, filePrefix, force) {
  const { month, year4chars } = getDateParts(date);
  const directory = join(CACHED_DIR, '' + year4chars);
  const rawDir = join(directory, 'raw');
  if (!fs.existsSync(directory)) {
    fs.mkdirSync(directory);
  }
  if (!fs.existsSync(rawDir)) {
    fs.mkdirSync(rawDir);
  }
  const rawFile = join(rawDir, `${filePrefix}-${year4chars}-${month}.csv`);
  if (fs.existsSync(rawFile) && !force) {
    console.log(`${filePrefix} data for ${readableDate(date)} already exists.`);
  } else {
    if (fs.existsSync(rawFile)) {
      console.log(
        `${filePrefix} data for ${readableDate(
          date
        )} already exists, but force=true, so let's get again.`
      );
    }
    console.log(`Loading ${filePrefix} data for ${readableDate(date)} from NHS digital website...`);
    const dataToCache = await rp({ uri });
    fs.writeFileSync(rawFile, dataToCache);
    console.log('File saved to local cache.');
  }
}

async function getDataFiles(fileUrls, force) {
  fileUrls = fileUrls.filter(Boolean); // remove undefined for months where no data
  for (const { date, maleUrl, femaleUrl, singleUrl, single5YrUrl } of fileUrls) {
    //data[dateString] = {};

    if (maleUrl && femaleUrl && singleUrl) {
      console.log(
        `For ${readableDate(
          date
        )} there appears to be a male, female and single url. This is unexpected and the codes needs changing to accommodate this.`
      );
      process.exit(1);
    }
    if (maleUrl && femaleUrl && single5YrUrl) {
      console.log(
        `For ${readableDate(
          date
        )} there appears to be a male, female and single 5yr url. This is unexpected and the codes needs changing to accommodate this.`
      );
      process.exit(1);
    }
    if (singleUrl && single5YrUrl) {
      console.log(
        `For ${readableDate(
          date
        )} there appears to be a single url and a single 5yr url. This is unexpected and the codes needs changing to accommodate this.`
      );
      process.exit(1);
    }
    if (!maleUrl && !femaleUrl && !singleUrl && !single5YrUrl) {
      console.log(
        `For ${readableDate(
          date
        )} there appears to be no urls. This is unexpected and the codes needs changing to accommodate this.`
      );
      process.exit(1);
    }

    if (maleUrl) {
      await downloadFileIfNotAlready(maleUrl, date, 'male', force);
    }
    if (femaleUrl) {
      await downloadFileIfNotAlready(femaleUrl, date, 'female', force);
    }
    if (singleUrl) {
      await downloadFileIfNotAlready(singleUrl, date, 'single', force);
    }
    if (single5YrUrl) {
      await downloadFileIfNotAlready(single5YrUrl, date, 'single5yr', force);
    }
  }
}

function processDataFiles(force) {
  fs.readdirSync(CACHED_DIR).forEach((year) => {
    const rawDir = join(CACHED_DIR, year, 'raw');
    const processedDir = join(CACHED_DIR, year, 'processed');
    if (!fs.existsSync(rawDir)) {
      console.log(
        `For the cached directory for ${year} there is no 'raw' directory. This is unexpected.`
      );
      process.exit(1);
    }
    if (!fs.existsSync(processedDir)) {
      fs.mkdirSync(processedDir);
    }
    fs.readdirSync(rawDir).forEach((rawFile) => {
      const rawFileStub = rawFile.replace('.csv', '');
      const processedFile = join(processedDir, `processed-${rawFileStub}.json`);
      if (fs.existsSync(processedFile)) {
        if (force) {
          console.log(
            `The raw file ${rawFile} has already been processed, but force=true, so we process again.`
          );
        } else {
          console.log(`The raw file ${rawFile} has already been processed. Moving on...`);
          return;
        }
      }

      const [prefix, year, month] = rawFileStub.split('-');
      const rawData = fs.readFileSync(join(rawDir, rawFile), 'utf8');

      switch (prefix) {
        case 'male':
          var maleData = processSingleSexFile(rawData, year, month, rawFile, 'male');
          fs.writeFileSync(processedFile, JSON.stringify(maleData, null, 2));
          break;
        case 'female':
          var femaleData = processSingleSexFile(rawData, year, month, rawFile, 'female');
          fs.writeFileSync(processedFile, JSON.stringify(femaleData, null, 2));
          break;
        case 'single':
          var data = processBothSexFile(rawData, rawFile);
          fs.writeFileSync(processedFile, JSON.stringify(data, null, 2));
          break;
        case 'single5yr':
          var data5yr = processBothSex5YearFile(rawData, rawFile);
          fs.writeFileSync(processedFile, JSON.stringify(data5yr, null, 2));
          break;
        default:
          console.log(`An unexpected prefix of '${prefix}' for ${rawFile}`);
          process.exit(1);
      }
    });
  });
}

function combineFiles() {
  const output = [];
  fs.readdirSync(CACHED_DIR).forEach((year) => {
    const processedDir = join(CACHED_DIR, year, 'processed');
    if (!fs.existsSync(processedDir)) {
      console.log(
        `For the cached directory for ${year} there is no 'processed' directory. This is unexpected.`
      );
      process.exit(1);
    }
    fs.readdirSync(processedDir).forEach((processedFile) => {
      console.log(`Loading and combining the data from ${processedFile}`);
      const data = JSON.parse(fs.readFileSync(join(processedDir, processedFile)));
      const [, , year, month] = processedFile.replace('.json', '').split('-');
      data.forEach((item) => {
        output.push(
          `${year},${+month},${item.ccg},${item.practiceId},${item.sex},${item.age},${
            item.frequency
          }`
        );
      });
    });
  });
  return output;
}

/**
 * The April 2017 file does not have CCGs. So instead we look at which CCG
 * each practice was associated with in the file before (Jan 2017) and the
 * file after (May 2017) and if no change then we use that
 */
let ccgLookup;
function getCCGLookup() {
  if (ccgLookup) return ccgLookup;
  ccgLookup = {};
  const file = join(CACHED_DIR, '2017', 'raw', 'single-2017-01.csv');
  const data = fs.readFileSync(file, 'utf8');
  data
    .split('\r\n')
    .slice(1)
    .filter((x) => x.length > 5)
    .forEach((row) => {
      const [practiceId, , ccgId] = row.split(',');
      //if (ccgs.indexOf(ccgId) > -1) {
      ccgLookup[practiceId] = ccgId;
      // between jan 2017 and april 2017 the 3 manchester ccgs (north, south, central)
      // merged into just manchester.
      if (['00W', '01M', '01N'].indexOf(ccgId) > -1) ccgLookup[practiceId] = '14L';
      //}
    });

  return ccgLookup;
}

function saveChunks(outputData) {
  // GitHub has a limit on file size, so let's keep this in chunks of ~50mb
  const chunkSize = 2000000; // 2M rows means file ~50mb
  let startRow = 0;
  for (let i = 0; startRow < outputData.length; i++) {
    const fileName = join(CHUNK_DIR, `gp-population-data-by-sex-and-age-chunk${i}.csv`);
    const data = outputData.slice(startRow, startRow + chunkSize);
    fs.writeFileSync(fileName, data.join('\n'));
    startRow += chunkSize;
  }
}

function combineChunks() {
  console.log('About to combine the chunked files.');
  const chunkFilenames = fs.readdirSync(CHUNK_DIR);
  console.log(`${chunkFilenames.length} chunks found.`);
  if (chunkFilenames.length === 0) {
    console.log('I expected at least one chunk.');
    process.exit(1);
  }
  let data = fs.readFileSync(join(CHUNK_DIR, chunkFilenames[0]), 'utf8');
  chunkFilenames.slice(1).forEach((filename, i) => {
    console.log(`Chunk ${i} processed.`);
    data += '\n' + fs.readFileSync(join(CHUNK_DIR, filename), 'utf8');
  });
  console.log(`Chunk ${chunkFilenames.length - 1} processed.`);
  fs.writeFileSync(OUTPUT_FILE, data);
  console.log(`Output file written to: ${OUTPUT_FILE}`);
}

async function compressOutput() {
  console.log('About to compress the output.');

  const output = fs.createWriteStream(OUTPUT_FILE_ZIPPED);
  const archive = archiver('zip', {
    zlib: { level: 9 }, // Sets the compression level.
  });
  archive.append(fs.createReadStream(OUTPUT_FILE), { name: OUTPUT_FILE_NAME });

  return new Promise((resolve) => {
    // listen for all archive data to be written
    // 'close' event is fired only when a file descriptor is involved
    output.on('close', function () {
      console.log(archive.pointer() + ' total bytes');
      console.log(`Output written to: ${OUTPUT_FILE_ZIPPED}`);
      resolve();
    });

    // good practice to catch warnings (ie stat failures and other non-blocking errors)
    archive.on('warning', function (err) {
      if (err.code === 'ENOENT') {
        // log warning
        console.log(err);
        resolve();
      } else {
        // throw error
        throw err;
      }
    });

    // good practice to catch this error explicitly
    archive.on('error', function (err) {
      throw err;
    });

    // pipe archive data to the file
    archive.pipe(output);
    archive.finalize();
  });
}

module.exports = {
  populateDateArray,
  getDataFileUrls,
  getDataFiles,
  processDataFiles,
  combineFiles,
  saveChunks,
  combineChunks,
  compressOutput,
};
