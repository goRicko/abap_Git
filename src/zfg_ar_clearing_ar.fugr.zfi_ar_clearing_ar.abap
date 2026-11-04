INCLUDE bdcrecxy.
FUNCTION zfi_ar_clearing_ar.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(CTU) LIKE  APQI-PUTACTIVE DEFAULT 'X'
*"     VALUE(MODE) LIKE  APQI-PUTACTIVE DEFAULT 'N'
*"     VALUE(UPDATE) LIKE  APQI-PUTACTIVE DEFAULT 'L'
*"     VALUE(GROUP) LIKE  APQI-GROUPID OPTIONAL
*"     VALUE(USER) LIKE  APQI-USERID OPTIONAL
*"     VALUE(KEEP) LIKE  APQI-QERASE OPTIONAL
*"     VALUE(HOLDDATE) LIKE  APQI-STARTDATE OPTIONAL
*"     VALUE(NODATA) LIKE  APQI-PUTACTIVE DEFAULT '/'
*"     VALUE(IV_AGKON_001) LIKE  BDCDATA-FVAL DEFAULT '8000'
*"     VALUE(IV_BUDAT_002) LIKE  BDCDATA-FVAL DEFAULT '15.10.2026'
*"     VALUE(IV_MONAT_003) LIKE  BDCDATA-FVAL DEFAULT '10'
*"     VALUE(IV_BUKRS_004) LIKE  BDCDATA-FVAL DEFAULT '1000'
*"     VALUE(IV_WAERS_005) LIKE  BDCDATA-FVAL DEFAULT 'IDR'
*"     VALUE(IV_XNOPS_006) LIKE  BDCDATA-FVAL DEFAULT 'X'
*"     VALUE(IV_XPOS1_01_007) LIKE  BDCDATA-FVAL DEFAULT ''
*"     VALUE(IV_XPOS1_03_008) LIKE  BDCDATA-FVAL DEFAULT 'X'
*"     VALUE(IV_SEL01_01_009) LIKE  BDCDATA-FVAL DEFAULT '1200000007'
*"     VALUE(IV_SEL01_02_010) LIKE  BDCDATA-FVAL DEFAULT '0100000005'
*"     VALUE(IV_ABPOS_011) LIKE  BDCDATA-FVAL DEFAULT '1'
*"     VALUE(IV_ABPOS_012) LIKE  BDCDATA-FVAL DEFAULT '1'
*"     VALUE(IV_PSZAH_01_013) LIKE  BDCDATA-FVAL DEFAULT ''
*"     VALUE(IV_ABPOS_014) LIKE  BDCDATA-FVAL DEFAULT '1'
*"     VALUE(IV_ABPOS_015) LIKE  BDCDATA-FVAL DEFAULT '1'
*"     VALUE(IV_WRBTR) LIKE  BDCDATA-FVAL OPTIONAL
*"  EXPORTING
*"     VALUE(SUBRC) TYPE  SYST-SUBRC
*"  TABLES
*"      MESSTAB STRUCTURE  BDCMSGCOLL OPTIONAL
*"----------------------------------------------------------------------

  DATA: lt_bdcdata TYPE TABLE OF bdcdata,
        lt_messtab TYPE TABLE OF bdcmsgcoll,
        ls_opt     TYPE ctu_params.

  CLEAR: bdcdata,
         messtab.

  PERFORM open_group      USING group user keep holddate ctu.

  PERFORM bdc_dynpro      USING 'SAPMF05A' '0131'.
  PERFORM bdc_field       USING 'BDC_CURSOR'
                                'RF05A-XPOS1(03)'.
  PERFORM bdc_field       USING 'BDC_OKCODE'
                                '=PA'.
  PERFORM bdc_field       USING 'RF05A-AGKON'
                                IV_AGKON_001.
  PERFORM bdc_field       USING 'BKPF-BUDAT'
                                IV_BUDAT_002.
  PERFORM bdc_field       USING 'BKPF-MONAT'
                                IV_MONAT_003.
  PERFORM bdc_field       USING 'BKPF-BUKRS'
                                IV_BUKRS_004.
  PERFORM bdc_field       USING 'BKPF-WAERS'
                                IV_WAERS_005.
  PERFORM bdc_field       USING 'RF05A-XNOPS'
                                'X'.
  PERFORM bdc_field       USING 'RF05A-XPOS1(01)'
                                ''.
  PERFORM bdc_field       USING 'RF05A-XPOS1(03)'
                                'X'.
  PERFORM bdc_dynpro      USING 'SAPMF05A' '0731'.
  PERFORM bdc_field       USING 'BDC_CURSOR'
                                'RF05A-SEL01(02)'.
  PERFORM bdc_field       USING 'BDC_OKCODE'
                                '=PA'.
  PERFORM bdc_field       USING 'RF05A-SEL01(01)'
                                IV_SEL01_01_009."'1200000007'.
  PERFORM bdc_field       USING 'RF05A-SEL01(02)'
                                IV_SEL01_02_010."'0100000005'.
  PERFORM bdc_dynpro      USING 'SAPDF05X' '3100'.
  PERFORM bdc_field       USING 'BDC_OKCODE'
                                '=PART'.
  PERFORM bdc_field       USING 'BDC_CURSOR'
                                'DF05B-PSSKT(01)'.
  PERFORM bdc_field       USING 'RF05A-ABPOS'
                                '1'.
  PERFORM bdc_dynpro      USING 'SAPDF05X' '3100'.
  PERFORM bdc_field       USING 'BDC_OKCODE'
                                '/00'.
  PERFORM bdc_field       USING 'BDC_CURSOR'
                                'DF05B-PSZAH(02)'.
  PERFORM bdc_field       USING 'RF05A-ABPOS'
                                '1'.
  PERFORM bdc_field       USING 'DF05B-PSZAH(01)'
                                IV_WRBTR."'                      1,500,000'.
  PERFORM bdc_dynpro      USING 'SAPDF05X' '3100'.
  PERFORM bdc_field       USING 'BDC_OKCODE'
                                '/00'.
  PERFORM bdc_field       USING 'BDC_CURSOR'
                                'DF05B-PSZAH(01)'.
  PERFORM bdc_field       USING 'RF05A-ABPOS'
                                '1'.
  PERFORM bdc_dynpro      USING 'SAPDF05X' '3100'.
  PERFORM bdc_field       USING 'BDC_OKCODE'
                                '=BU'.
  PERFORM bdc_field       USING 'BDC_CURSOR'
                                'DF05B-PSZAH(01)'.
  PERFORM bdc_field       USING 'RF05A-ABPOS'
                                '1'.
*  PERFORM bdc_transaction USING 'F-32'.


*  PERFORM open_group      USING group user keep holddate ctu.

*  PERFORM bdc_dynpro      USING 'SAPMF05A' '0122'.
*  PERFORM bdc_field       USING 'BDC_CURSOR'
*                              'RF05A-XPOS1(04)'.
*  PERFORM bdc_field       USING 'BDC_CURSOR'
*                                'BKPF-BKTXT'.
*  PERFORM bdc_field       USING 'BDC_OKCODE'
*                                '=SL'.
*  PERFORM bdc_field       USING 'BKPF-BLDAT'
*                                iv_bldat_001.
*  PERFORM bdc_field       USING 'BKPF-BLART'
*                                iv_blart_002.
*  PERFORM bdc_field       USING 'BKPF-BUKRS'
*                                iv_bukrs_003.
*  PERFORM bdc_field       USING 'BKPF-BUDAT'
*                                iv_budat_004.
*  PERFORM bdc_field       USING 'BKPF-MONAT'
*                                iv_monat_005.
*  PERFORM bdc_field       USING 'BKPF-WAERS'
*                                iv_waers_006.
*  PERFORM bdc_field       USING 'BKPF-XBLNR'
*                                iv_xblnr_007.
*  PERFORM bdc_field       USING 'BKPF-BKTXT'
*                                iv_bktxt_008.
*  PERFORM bdc_field       USING 'FS006-DOCID'
*                                iv_docid_009.
*  PERFORM bdc_dynpro      USING 'SAPMF05A' '0710'.
*  PERFORM bdc_field       USING 'BDC_CURSOR'
*                                'RF05A-XPOS1(04)'.
*  PERFORM bdc_field       USING 'BDC_OKCODE'
*                                '=PA'.
*  PERFORM bdc_field       USING 'RF05A-AGBUK'
*                                iv_agbuk_010.
*  PERFORM bdc_field       USING 'RF05A-AGKON'
*                                iv_agkon_011.
*  PERFORM bdc_field       USING 'RF05A-AGKOA'
*                                iv_agkoa_012.
*  PERFORM bdc_field       USING 'RF05A-XNOPS'
*                                iv_xnops_013.
*  PERFORM bdc_field       USING 'RF05A-XPOS1(01)'
*                                ''.
*  PERFORM bdc_field       USING 'RF05A-XPOS1(03)'
*                                'X'.
*  PERFORM bdc_dynpro      USING 'SAPMF05A' '0731'.
*  PERFORM bdc_field       USING 'BDC_CURSOR'
*                                'RF05A-SEL01(02)'.
*  PERFORM bdc_field       USING 'BDC_OKCODE'
*                                '=PA'.
*  PERFORM bdc_field       USING 'RF05A-SEL01(01)'
*                                iv_sel01_01_016."  '1200000007'.
*  PERFORM bdc_field       USING 'RF05A-SEL01(02)'
*                                iv_sel01_02_017.    "'0100000005'.
*  PERFORM bdc_dynpro      USING 'SAPDF05X' '3100'.
*  PERFORM bdc_field       USING 'BDC_OKCODE'
*                                '=PART'.
*  PERFORM bdc_field       USING 'BDC_CURSOR'
*                                'DF05B-PSSKT(01)'.
*  PERFORM bdc_field       USING 'RF05A-ABPOS'
*                                '1'.
*  PERFORM bdc_dynpro      USING 'SAPDF05X' '3100'.
*  PERFORM bdc_field       USING 'BDC_OKCODE'
*                                'PART'.
*  PERFORM bdc_field       USING 'BDC_CURSOR'
*                                'DF05B-PSZAH(01)'.
*  PERFORM bdc_field       USING 'RF05A-ABPOS'
*                                '1'.
*  PERFORM bdc_field       USING 'DF05B-PSZAH(01)'
*                                '                      1,500,000'.
*  PERFORM bdc_dynpro      USING 'SAPDF05X' '3100'.
*  PERFORM bdc_field       USING 'BDC_OKCODE'
*                                '=BU'.
*  PERFORM bdc_field       USING 'BDC_CURSOR'
*                                'DF05B-PSZAH(01)'.
*  PERFORM bdc_field       USING 'RF05A-ABPOS'
*                                '1'.

  CALL TRANSACTION 'F-32'
  USING      bdcdata
  OPTIONS FROM ls_opt
  MESSAGES INTO messtab.

  PERFORM close_group USING     ctu.


ENDFUNCTION.
